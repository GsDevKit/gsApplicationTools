accessing
serverClass: aServerClass
  "store association so class reference survives new class versions"

  serverClassAssoc := (((GsSession currentSession symbolList
    dictionariesAndSymbolsOf: aServerClass) at: 1) at: 1 ) at: aServerClass name