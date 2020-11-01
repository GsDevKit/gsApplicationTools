accessing
transactionMode: aSymbol
  "#autoBegin or #manualBegin"

  "Use doBasicTransaction and repeat till success instead of throwing an exception,
  because it is likely to run into transaction conflicts here if server starts up with multiple processes."

  [	self doBasicTransaction: [ transactionMode := aSymbol ]
  ]	whileFalse:[(Delay forMilliseconds: (Random new integerBetween: 0 and: 150)) wait].
  
  System transactionMode == aSymbol
    ifFalse: [ System transactionMode: aSymbol ]
