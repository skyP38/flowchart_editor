// Базовая модель данных блока на блок-схеме
sealed class GostNodeData {
  // Текст внутри блока
  final String text;
  const GostNodeData(this.text);

  // Возвращает копию с измененным текстом
  GostNodeData copyWith({String? text});
}

// Прямоугольник - вычислительный процесс
class ProcessBlock extends GostNodeData {
  const ProcessBlock(super.text);
  @override
  ProcessBlock copyWith({String? text}) => ProcessBlock(text ?? this.text);
}

// Ромб - проверка условия
class LogicBlock extends GostNodeData {
  const LogicBlock(super.text);
  @override
  LogicBlock copyWith({String? text}) => LogicBlock(text ?? this.text);
}

// Скругленный прямоугольник - начало/конец
class TerminalBlock extends GostNodeData {
  const TerminalBlock(super.text);
  @override
  TerminalBlock copyWith({String? text}) => TerminalBlock(text ?? this.text);
}

// Параллелограмм - ввод/вывод
class IOBlock extends GostNodeData {
  const IOBlock(super.text);
  @override
  IOBlock copyWith({String? text}) => IOBlock(text ?? this.text);
}

// Прямоугольник с двойными боковыми линиями - подпрограмма
class SubroutineBlock extends GostNodeData {
  const SubroutineBlock(super.text);
  @override
  SubroutineBlock copyWith({String? text}) =>
      SubroutineBlock(text ?? this.text);
}

// Шестиугольник - цикл For
class ForBlock extends GostNodeData {
  const ForBlock(super.text);
  @override
  ForBlock copyWith({String? text}) => ForBlock(text ?? this.text);
}
