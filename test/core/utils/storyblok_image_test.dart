import 'package:animewitcher/core/utils/storyblok_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('asks for the stored width instead of the catalog thumbnail', () {
    expect(
      storyblokAtStoredWidth(
        'https://a.storyblok.com/f/178900/1460x821/bc4fc3f4be/kaiju.jpg'
        '/m/576x0/filters:quality(95)format(webp)',
      ),
      'https://a.storyblok.com/f/178900/1460x821/bc4fc3f4be/kaiju.jpg'
      '/m/1460x0/filters:quality(95)format(webp)',
    );
  });

  test('caps at the requested maximum', () {
    expect(
      storyblokAtStoredWidth(
        'https://a.storyblok.com/f/178900/1920x1080/7e8750f590/db.png'
        '/m/576x0/filters:quality(95)format(webp)',
        maxWidth: 1200,
      ),
      'https://a.storyblok.com/f/178900/1920x1080/7e8750f590/db.png'
      '/m/1200x0/filters:quality(95)format(webp)',
    );
  });

  test('leaves a render alone when it already asks for enough', () {
    const url =
        'https://a.storyblok.com/f/178900/640x368/17472a578f/fungus.png'
        '/m/1200x0/filters:quality(95)format(webp)';
    expect(storyblokAtStoredWidth(url), url);
  });

  test('never asks past the stored width, even when the cap is higher', () {
    // Storyblok does not upscale, so a bigger ask would return the stored
    // image anyway — the url should say what it will actually get.
    expect(
      storyblokAtStoredWidth(
        'https://a.storyblok.com/f/178900/960x540/abc/small.jpg'
        '/m/576x0/filters:quality(95)',
        maxWidth: 1920,
      ),
      'https://a.storyblok.com/f/178900/960x540/abc/small.jpg'
      '/m/960x0/filters:quality(95)',
    );
  });

  test('the per-device banner width is a sane render size', () {
    // Desktop takes the full stored image; a phone's hero is a quarter the
    // width, so it asks for far less than the desktop cap.
    expect(storyblokBannerWidth, anyOf(1080, 1920));
  });

  test('leaves other hosts untouched', () {
    const url = 'https://s4.anilist.co/file/anilistcdn/media/anime/cover/x.jpg';
    expect(storyblokAtStoredWidth(url), url);
  });

  test('leaves a Storyblok url with no render directive untouched', () {
    const url = 'https://a.storyblok.com/f/178900/1460x821/abc/kaiju.jpg';
    expect(storyblokAtStoredWidth(url), url);
  });
}
