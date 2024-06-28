service instance-server
startServerOn: portOrResourceName
  "start server in current vm. Not expected to return."

  | shouldListenForDebug |
  shouldListenForDebug := [ (System gemEnvironmentVariable: 'SeasideGemServerShouldListenForDebug') = 'true' ]
    on: Error
    do: [:ex | ex return: false].
  shouldListenForDebug ifTrue: [System listenForDebugServer].
  self startBasicServerOn: portOrResourceName.
  [ true ] whileTrue: [ (Delay forSeconds: 10) wait ]
