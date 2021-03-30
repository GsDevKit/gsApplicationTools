tasks
scheduleBreakpointTask
  ^ (self taskClass
    value: [ 
      | meth sel cls |
      sel := #'breakpointMethod'.
      cls := self class whichClassIncludesSelector: sel asString.
      meth := cls compiledMethodAt: sel.
		GemServer setBreakIn: meth atStepPoint: 1.
      GsProcess usingNativeCode
        ifTrue: [ 
          | p |
          p := GsProcess _current.
          [ p convertToPortableStack ] fork.
          Processor yield ].
      GemServer enableBreakPoints.
      self breakpointMethod ])
    addToQueue: self