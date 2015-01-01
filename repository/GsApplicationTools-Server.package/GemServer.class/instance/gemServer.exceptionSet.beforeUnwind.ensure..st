gem server api
gemServer: aBlock exceptionSet: exceptionSet beforeUnwind: beforeUnwindBlock ensure: ensureBlock
  [ 
  ^ aBlock
    on: exceptionSet
    do: [ :ex | 
      | exception |
      [ 
      "only returns if an error was logged"
      exception := ex.
      self handleGemServerException: ex.
      beforeUnwindBlock value: exception ]
        on: Error
        do: [ :unexpectedError | 
          "error while handling the exception"
          self
            serverError: unexpectedError
            titled: self name , ' Internal Server error handling exception: '.
          beforeUnwindBlock value: unexpectedError.
          self doInteractiveModePass: unexpectedError.
          unexpectedError return: nil	"unwind error stack" ].
      self doInteractiveModePass: exception.
      self	"unwind stack" ] ]
    ensure: ensureBlock