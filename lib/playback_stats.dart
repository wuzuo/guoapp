import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class FrameStats {
  FrameStats._();

  static bool _installed = false;
  static DateTime _window = DateTime.now();
  static int _frames = 0;
  static int _uiMax = 0;
  static int _rasterMax = 0;
  static int _jank = 0;

  static void install() {
    if (_installed) return;
    _installed = true;
    _window = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        _frames++;
        final ui = timing.buildDuration.inMilliseconds;
        final raster = timing.rasterDuration.inMilliseconds;
        if (ui > _uiMax) _uiMax = ui;
        if (raster > _rasterMax) _rasterMax = raster;
        if (ui > 32 || raster > 32) _jank++;
      }
      final now = DateTime.now();
      if (now.difference(_window).inSeconds < 5) return;
      debugPrint(
        '[frame] n=$_frames uiMax=${_uiMax}ms rasterMax=${_rasterMax}ms jank=$_jank',
      );
      _window = now;
      _frames = 0;
      _uiMax = 0;
      _rasterMax = 0;
      _jank = 0;
    });
  }
}
