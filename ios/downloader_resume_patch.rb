# background_downloader 9.5.9 discards resume data after a final failure on
# Dart's side. URLSession already supplied a resumable checkpoint here: emit
# paused for that case so both the checkpoint and its temporary bytes survive.
def patch_background_downloader_resumable_failures(plugin_dir)
  file = File.join(plugin_dir, 'UrlSessionDelegate.swift')
  source = File.read(file)
  marker = '// AnimeWitcher: retain URLSession checkpoints on resumable errors'
  return if source.include?(marker)

  needle = 'let canResume = resumeData != nil && processResumeData(task: bgdTask, resumeData: resumeData!)'
  raise 'background_downloader resume marker changed' unless source.include?(needle)

  source.sub!(needle, needle + <<~SWIFT)

                  #{marker}
                  if canResume && isDownloadTask(task: bgdTask) &&
                      (error! as NSError).code != NSURLErrorCancelled {
                      processStatusUpdate(task: bgdTask, status: .paused)
                      BDPlugin.propertyLock.withLock({
                          _ = BDPlugin.progressInfo.removeValue(forKey: bgdTask.taskId)
                          BDPlugin.initialResponseDataProcessed.remove(bgdTask.taskId)
                      })
                      return
                  }
  SWIFT
  File.write(file, source)
end
