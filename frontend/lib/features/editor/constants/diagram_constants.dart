class NodeConstants {
  NodeConstants._();
  static const double defaultWidth = 160;
  static const double defaultHeight = 80;
  static const double minWidth = 80;
  static const double minHeight = 40;
  static const double textPadding = 16;
  static const double handleSize = 24;
  static const double handleInnerSize = 14;
  static const double handleOffset = -14;
  static const double handleRightOffset = -12;
  static const double startPadding = 70;
}

class LayoutConstants {
  LayoutConstants._();
  static const double stepXExtra = 70;
  static const double stepYExtra = 48;
  // Дополнительный горизонтальный шаг на каждый уровень вложенности For.
  static const double loopbackChannelWidth = 15;
  // Дополнительный вертикальный шаг на каждый уровень вложенности For.
  static const double loopbackChannelHeight = 8;
  static const double startPadding = 70;
  static const double rankGap = 50;
  static const double bodyOffsetY = 30;
  static const double exitOffsetX = 40;
  static const double endExtraOffset = 80;
  static const double bodyIndentX = 0;
}

class ConnectionConstants {
  ConnectionConstants._();
  static const double loopbackGap = 20;
  static const double exitRightOffset = 30;
  static const double exitTurnOffsetY = 40;
  static const double noSafeXOffset = 20;
  static const double endLineOffset = 0;
  static const double endOffsetY = 10;
  static const double hitDistance = 15;
  static const double hitStep = 2;
  static const double loopbackBaseGap = 20;
  static const double loopbackDepthStep = 20;
  static const double exitDepthStep = 40;

  static const double noDepthStep = 10;
  static const double noDepthOffsetMax = 200;
}

class GridConstants {
  GridConstants._();
  static const double fontSize = 18;
  static const double stepXExtra = 70;
  static const double stepYExtra = 40;
  static const double labelTopY = 2;
  static const double labelLeftX = 2;
}

class InsertionPointConstants {
  InsertionPointConstants._();
  static const double radius = 10;
  static const double hitRadius = 12;
  static const double plusSize = 4;
  static const double strokeWidth = 2;
}

class SelectionConstants {
  SelectionConstants._();
  static const double fillOpacity = 0.3;
  static const double borderWidth = 1.5;
}

class CanvasConstants {
  CanvasConstants._();
  static const double minWidth = 1200;
  static const double minHeight = 800;
  static const double padding = 400;
  static const double defaultWidth = 1500;
  static const double defaultHeight = 1000;
}

class HistoryConstants {
  HistoryConstants._();
  static const int maxHistorySize = 50;
}

class ScaleConstants {
  ScaleConstants._();
  static const double minScale = 0.5;
  static const double maxScale = 3.0;
  static const double zoomFactor = 0.01;
  static const double scaleDeltaMultiplier = 100;
}

class SvgConstants {
  SvgConstants._();
  static const String fontFamily = 'Arial';
  static const double fontSize = 14;
  static const double gridFontSize = 18;
  static const String gridColor = '#666666';
}
