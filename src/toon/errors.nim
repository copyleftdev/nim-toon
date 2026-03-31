type
  ToonErrorKind* = enum
    teSyntax
    teIndentation
    teStructure
    teValidation
    teConflict

  ToonError* = object of CatchableError
    kind*: ToonErrorKind
    line*: int
    column*: int

proc newToonError*(
  kind: ToonErrorKind,
  message: string,
  line = 0,
  column = 0,
): ref ToonError =
  result = newException(ToonError, message)
  result.kind = kind
  result.line = line
  result.column = column
