gsApplicationTools [![Build Status](https://github.com/GsDevKit/gsApplicationTools/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/GsDevKit/gsApplicationTools/actions/workflows/ci.yml) 
==================



This repository includes scripts and code that allow a more convenient setup of a Gemstone server application 

## GemStone Installation

```Smalltalk
Gofer new
  package: 'GsUpgrader-Core';
  url: 'http://ss3.gemtalksystems.com/ss/gsUpgrader';
  load.
(Smalltalk at: #GsUpgrader) upgradeGrease.

GsDeployer deploy: [
  "Load GsApplicationTools packages"
  Metacello new
    baseline: 'GsApplicationTools';
    repository: 'github://GsDevKit/gsApplicationTools:master/repository';
    load: #('default')
].
```

## Docs

- [Getting started with Gem Servers](https://github.com/GsDevKit/gsApplicationTools/blob/master/docs/gettingStarted.md#table-of-contents)

## Questions [![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/GsDevKit/gsApplicationTools?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

1. [Gitter chat](https://gitter.im/GsDevKit/gsApplicationTools)
2. [GLASS mailing list](http://lists.gemtalksystems.com/mailman/listinfo/glass)
