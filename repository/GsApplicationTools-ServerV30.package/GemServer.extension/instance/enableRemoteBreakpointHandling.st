*gsapplicationtools-serverv30
enableRemoteBreakpointHandling
  "Enable remote Breakpoing handling"

  self enableRemoteBreakpoints
    ifFalse: [ ^ self ].
  self
    scriptLogEvent: 'enableRemoteBreakpointHandling: ' , self name
    object: self.
  self class enableBreakPoints.
  GemToGemAnnouncement installStaticHandler.
  System _commitPrintingDiagnostics
    ifFalse: [ self error: 'Could not commit for GemToGemSignaling' ].
  GemToGemAnnouncement announcer
    on: ClearAllBreakpointsAnnouncement send: #'clearAllBreakpoints:' to: self;
    on: SetOrClearBreakpointAnnouncement
      send: #'setOrClearBreakpoint:'
      to: self