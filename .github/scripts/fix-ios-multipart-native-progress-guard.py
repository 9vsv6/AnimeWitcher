from pathlib import Path

path = Path('ios/Runner/DownloadNativeWaitingQueue.swift')
text = path.read_text()

old = '''    if state.transferringTaskIds.contains(parentId) {
      state.runningSamples[parentId] = RunningSample(
'''
new = '''    let parentIsTransferring = state.transferringTaskIds.contains(parentId)
    if parentIsTransferring {
      state.runningSamples[parentId] = RunningSample(
'''
if text.count(old) != 1:
    raise SystemExit(f'expected one multipart parent ownership branch, found {text.count(old)}')
text = text.replace(old, new, 1)

old = '    let shouldUpdateNativeOverlay = completed || now - lastOverlay >= chunkBridgeInterval\n'
new = '''    let shouldUpdateNativeOverlay = parentIsTransferring
      && (completed || now - lastOverlay >= chunkBridgeInterval)
'''
if text.count(old) != 1:
    raise SystemExit(f'expected one multipart overlay throttle, found {text.count(old)}')
text = text.replace(old, new, 1)

path.write_text(text)
print('Guarded native multipart overlay updates by logical parent ownership.')
