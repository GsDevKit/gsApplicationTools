#Debugging Gem Servers with tODE

##Table of Contents
1. [Introduction](#introduction)
2. [Gem Server Example](#gem-server-example)
  1. [GemServerRemoteServerTransactionModelBExample](#gemserverremoteservertransactionmodelbexample)
    1. [Gem Server Registration](#gem-server-registration)
    2. [Gem Server Start/Stop/Restart/Status](#gem-server-startstoprestartstatus)
  2. [GemServerRemoteClientTransactionModelBExample](#gemserverremoteclienttransactionmodelbexample)
    1. [Client Poll for Results](#client-poll-for-results)
    2. [Client Task Scheduling](#client-task-scheduling)
3. [tODE Debugging](#tode-debugging)
4. [Gem Server Installation](#gem-server-installation)
5. [GemStone Processes and GCI](#gemstone-processes-and-gci)
6. [Appendix](#appendix)
  1. [`mount` man page](#mount-man-page)
  2. [`project entry` man page](#project-entry-man-page)
  3. [`project load` man page](#project-load-man-page)
  4. [tODE `example` script](#tode-example-script)
  5. [tODE `example` script man page](#tode-example-script-man-page)

##Introduction
In this tutorial we will go over the steps necessary to debug a *gem server* using tODE.

When debugging a gem server in tODE, [the UI process is blocked](#gemstone-processes-and-gci), which means that it is necessary to run two tODE images: one running as the client and one running as the server.

Let's open two *small* tODE clients and position the client image on the top half of the screen and the server image on bottom half of the screen. 
Use the *alternate-large* window layout (**tODE>>tODE Window Layout>>alternate-large** menu item).
The **alternate** layouts are designed to be useable with minimal vertical screen real estate.

While the half-screen images are usable for running client and server code, it is convenient to have a third tODE client that is opened to full screen size for reading and writing code.

When running with multiple tODE clients connected to the same stone, remember to use the tODE `abort` command whenever you start work in a different tODE client.

In the *development* client, log into your development stone and install the **GsApplicationTools** project, including the example gem servers, by following the [Gem Server Installation instructions](#gem-server-installation).

##Gem Server Example

###GemServerRemoteServerTransactionModelBExample
In this tutorial we will be using the class **GemServerRemoteServerTransactionModelBExample** as our example gem server. This gem server operates by taking tasks off of an RcQueue (**processTasksOnQueue**) and processes each task in a separate thread (**taskServiceThreadBlock:**):

```Smalltalk
processTasksOnQueue
  | tasks |
  self
    doSimpleTransaction: [ 
      tasks := self queue removeAll.
      self inProcess addAll: tasks ].
  self trace: [ 'tasks [1] ' , tasks size printString ] object: [ tasks copy ].
  tasks
    do: [ :task | 
      | proc |
      self trace: [ 'fork task [2] ' , task label ] object: [ task ].
      proc := TransientStackValue
        value: (self taskServiceThreadBlock: task) fork.
      activeProcessesMutex critical: [ self activeProcesses add: proc value ].
      self
        trace: [ 
          'task [5] inProcess: ' , self inProcess size printString , ' activeProcesses: '
            , self activeProcesses size printString ]
        object: [ self status ].
      Processor yield ]
```

```Smalltalk
taskServiceThreadBlock: task
  "use GemServer>>gemServerTransaction:exceptionSet:onError: to wrap a transaction around 
   the gemServerTransaction and onError blocks ... 'seaside-stye' transaction model"

  ^ [ 
  [ 
  self
    gemServerTransaction: [ 
      "handle exceptions (including breakpoints and Halt) that occur while processing individual task"
      self trace: [ 'start process task [3] ' , task label ] object: [ task ].
      [ task processTask: self ]
        ensure: [ 
          self inProcess remove: task.
          self trace: [ 'end process task [4] ' , task label ] object: [ task ] ] ]
    exceptionSet:
      GemServerRemoteInternalServerErrorTriggerExample , self gemServerExceptionSet
    onError: [ :ex | 
      task exception: ex.
      (ObjectLogEntry
        error: 'Server example task exception: ' , ex description printString
        object: task) addToLog ] ]
    ensure: [ 
      activeProcessesMutex
        critical: [ self activeProcesses value remove: Processor activeProcess ifAbsent: [  ] ] ] ]
```

When an errors occurs, the error is logged in the object log and in the gem log:

```Smalltalk
logStack: exception titled: title inTransactionDo: inTransactionBlock
  | stream stack exDescription |
  stack := GsProcess stackReportToLevel: 300.
  exDescription := exception description.
  System inTransaction
    ifTrue: [ 
      self createContinuation: exDescription.
      inTransactionBlock value ]
    ifFalse: [ 
      self
        doSimpleTransaction: [ 
          self createContinuation: exDescription.
          inTransactionBlock value ] ].
  stream := WriteStream on: String new.
  stream nextPutAll: '----------- ' , title , DateAndTime now printString.
  stream lf.
  stream nextPutAll: exDescription.
  stream lf.
  stream nextPutAll: stack.
  stream nextPutAll: '-----------'.
  stream lf.
  GsFile gciLogServer: stream contents
```

####Gem Server Registration
For debugging purposes, you will create a gem server using the following expression:

```Smalltalk
(GemServerRemoteServerTransactionModelBExample register: 'example')
    tracing: true;
    interactiveMode: true;
    yourself
```

Setting `tracing: true` means that the **trace:object** calls as seen in the server code above will be recorded in the object log.

Setting `interactiveMode: true` means that instead of logging errors to object log, the exceptions will be passed so that a debugger will be opened in the tODE server client.

####Gem Server Start/Stop/Restart/Status

Once a server has been registered, the following Smalltalk expressions can be used:

```Smalltalk
(GemServerRegistry gemServerNamed: 'example') start
(GemServerRegistry gemServerNamed: 'example') restart
(GemServerRegistry gemServerNamed: 'example') stop
(GemServerRegistry gemServerNamed: 'example') status
```

Note that these commands are meant to be used in interactive mode and will launch/terminate processes in the current image. Note that the `start` and `restart` messages will cause the UI to block.

###GemServerRemoteClientTransactionModelBExample
The gem server client schedules tasks.

A task is an instance of class **GemServerRemoteTaskTransactionModelBExample**.
*tasks* are created with a block to be processed:

```Smalltalk
GemServerRemoteTaskTransactionModelBExample 
  value: [ (HTTPSocket httpGet: 'http://example.com') contents ]
```

####Client Poll for Results
Once a task has been scheduled, the client polls for a result:

```Smalltalk
  completed := false.
  [ completed ]
    whileFalse: [ 
      (Delay forSeconds: 1) wait.
      completed := task hasValue or: [ task hasError ] ]
```

A task is *completed* if processing resulted in a *value* or an *error*.
If an *error* occured, the exception is recorded with the task.

If a task has an *error*, then you can look in the object log for a corresponding continuation and debug the continuation.

A task is *valid* if the result of processing was as expected.
If a task is supposed to return a value, then it is valid if it *hasValue*.
If a task is supposed to result in an error, then it is valid if it *hasError* and the *exception* matches the *expectedException*.

####Client Task Scheduling
The gem server client (**GemServerRemoteClientTransactionModelBExample**) has the following collection of pre-defined tasks defined:

```
scheduleBreakpointTask
scheduleErrorTask
scheduleExampleHttpTask
scheduleFastTask
scheduleHaltTask
scheduleInternalServerError
scheduleOutOfMemoryPersistent
scheduleOutOfMemoryTemp
scheduleSimpleTask
scheduleStackOverflow
scheduleStatusTask
scheduleTimeInLondonTask
scheduleWarning
```

The `scheduleBreakpointTask`, `scheduleErrorTask`, `scheduleHaltTask` tasks can be used to simulate development activity 

Tasks can be scheduled on the server by executing the following in the client image:

```Smalltalk
  | gemServer client task result |
  gemServer := GemServerRegistry gemServerNamed: 'example'.
  client := gemServer clientClass new.
  task := client scheduleErrorTask.
  task label: 'scheduleErrorTask'.
  client doCommitTransaction.
  ^ client waitForTasks: {task} gemServer: gemServer
```

The result of the **waitForTasks:gemServer:** message is an array like the following:

```Smalltalk
  {true.                                   "true if all tasks returned a proper value"
  tasks.                                   "array of tasks passed in as argument"
  completed.                               "array of completed tasks"
  valid.                                   "array of valid, completed tasks"
  status.                                  "#success, #timedOut, or #crashed"
  (valid collect: [ :each | each value ]). "result value of task"
  (self inProcess).                        "collection of tasks in process"
  (self queue)                             "collection of tasks awaiting processing"
  }    
```

##tODE Debugging
##Gem Server Installation
Use the following tODE expressions to install the **GemServer** support code and a set of example gem servers:

```
project entry --baseline=GsApplicationTools --repo=github://GsDevKit/gsApplicationTools/repository \
        /sys/stone/projects
project load GsApplicationTools
mount @/sys/stone/dirs/GsApplicationTools/tode /home gemserver
```

The [`project entry` command](#project-entry-man-page) creates a *project entry* in the *project list* for this stone (`/sys/stone/projects`). 
If you want to have the **GsApplicationTools** project show up in *project list* for all of your stones, then create the *project entry* in the `/sys/local/projects` node:

```
project entry --baseline=GsApplicationTools --repo=github://GsDevKit/gsApplicationTools/repository \
        /sys/local/projects
```

The [`project load` command](#project-load-man-page) loads the project as specified by the  *project entry* in the *project list*.

The [`mount` command](#mount-man-page) makes the `tode` directory of the **GsApplicationTools** checkout available from within tODE as the node `/home/gemserver`. Again, if you want the `tode` directory to be available at the some location for all of your stones, use the following command:

```
mount @/sys/stone/dirs/GsApplicationTools/tode /sys/local/home gemserver
```

##GemStone Processes and GCI

In order for GemStone Smalltalk code to execute in a GCI[1] application like tODE, the client process must make a blocking or non-blocking GCI call. 
However, one is not allowed to make multiple, concurrent GCI calls to execute Smalltalk code for the same gem process, so in effect the GCI interface is single threaded with respect to executing GemStone Smalltalk code.
Since nearly all of tODE's functionality is implemented in GemStone Smalltalk code, it is not practical to allow developers to do much other than wait for processing to complete on the gem.
tODE uses a non-blocking GCI call to initiate execution of GemStone Smalltalk code and spins in a restless loop polling for the result making it possible to interrupt GemStone processing by using the **ALT-.** key combination.

##Appendix

###*mount* man page
```
NAME
  mount - mount file directory into tODE object structure

SYNOPSIS
  mount [-h|--help]
  mount [--asLeafNode] <directory-or-file-path> <object-path> [<link-name>]
  mount [--asLeafNode] @<directory-instance-path> <object-path> [<link-name>]
  mount [--asLeafNode] [--todeRoot | --stoneRoot] <relative-directory-or-file-path> <object-path> [<link-name>]

DESCRIPTION
  The `mount` command makes it possible to create a link between the server
  file system and the tODE object structure.

  Once a file system directory or file has been mounted, you can navigate the file system
  as if it were part of the tODE object structure.

  Files with a `.ston` extension are expected to contain object references 
  serialized using STON and tODE will automatically materialize the objects 
  on reference.

  If a <link-name> is not specified, the last element of the <directory-path>
  is used to name the link node.

OPTIONS
  --help 
    Bring up this man page.

  --asLeafNode
    By default nodes are mounted such that visitors will traverse the children of the
    node. The typical visitor is recursively searching the node tree for TDLeafNodes and
    is looking for senders or references to globals in Smalltalk code. If the mount point
    is for a pure filesystem (like the root node of a git repository), you probably
    do not want a senders search traversing the entire git repository. Using
    --asLeafNode will terminate visiting at the gateway node and the gateway node
    itself will be searched for references. 

  --stoneRoot
    The <relative-directory-or-file-path> is interpreted as a directory path relative to 
    `<todeRoot>/sys/stones/stones/<stone-name>`, where <todeRoot> is defined by the 
    `serverTodeRoot` field of the current sessionDescription (instance of TDSessionDescription).
    Use `/` to indicate an empty relative path, i.e., mount <stoneRoot> directly.

  --todeRoot
    The <relative-directory-or-file-path> is interpreted as a path relative to `todeRoot` which 
    is specified by the `serverTodeRoot` field of the current sessionDescription (instance 
    of TDSessionDescription). TDTopezServer>>serverTodeRoot: may be used to dynamically change
    `serverTodeRoot` for the duration of the session. Use `/` to indicate an empty relative path, 
    i.e., mount <todeRoot> directly.

EXAMPLES
  mount -h

  mount /opt/git/todeHome/home /
  mount /opt/git/todeHome/home / todeHome
  mount /opt/git/todeHome/home.ston / todeHome

  mount --todeRoot / / home
  mount --stoneRoot / /sys stone

  mount @/sys/stone/dirs/GsApplicationTools/tode /home gemServer

  NOTE - use the `tode it` menu item to run the examples directly from this window.

SEE ALSO
  edit /tools/shell/bin/mount
browse method --spec `TDShellTool class>>mount`

  NOTE - use the `tode it` menu item to run the commands directly from this window.
```
###*project entry* man page
```
NAME
  project entry - Create a new project entry

SYNOPSIS
  project entry --baseline=<project-name> --repo=<project-repo> [--loads=<load-expression>] \ 
                <project-path>
          entry --config=<project-name> [--version=<project-version>] \
                --repo=<project-repo> [--loads=<load-expression>] <project-path>
          entry --git=<project-name> [--repo=<git-repo-path>] <project-path>

DESCRIPTION
  The project entry specifies project options used by the `project list` window.

  A project entry can be created for loaded projects or for projects that have
  yet to be loaded. 

  There are two basic types of project entry: Git and Metacello. 

  For Git project entries you define the name of the project and the location on 
  disk where the git repository is located. For example:

    project entry --git=projectHome --repo=$GS_HOME /home/external

  For Metacello project entries you define the name of the project, the type of
  the project (baseline or configuration), the repository where the baseline or
  configuration may be found, and (optionally) the package/project/groups to be loaded.
  For configurations, you also specify the version of the project to be loaded. For example:

    project entry --config=External                          \
                  --version=1.0.0                            \
                  --repo=http://ss3.gemtalksystems.com/ss/external \
                  --loads=`#('Core')`                      \
                  /home/external

    project entry --baseline=External                                    \
                  --repo=github://dalehenrich/external:master/repository \
                  /home/external

  If you don't specify a `--loads` option, the 'default' group is loaded. Once you have 
  created a project entry, you may change or add attributes. For example, you may want to 
  change the status to #inactive.

  Once a project is loaded, only changes to the loads specification, locked
  attribute and active attribute may have an effect. The remaining information
  is taken directly from the loaded project itself.

  Any changes you make will take effect after the project list is refreshed.

Project Entry Attributes

  status
    When a project entry is initially created, the status is set to #active. Active
    projects are listed in bold and sorted near the top of the project list.

  gitRootPath
    For projects use github repositories, the gitRootPath specifies a location on 
    disk where the git repository should be located. This attribute is used by the
    `project clone` command. If a project entry does not have the gitRootPath
    explicitly set, then the path returned by 
    TDProjectEntryDefinition class>>defaultGitRootPath is used. The value of
    TDProjectEntryDefinition class>>defaultGitRootPath can be set on a session
    by session basis.

  locked
    For Metacello projects, you may  specify that the project entry is locked. By
    locking a project entry you can ensure that the specified project version (if 
    applicable) and repository will be used whenever the project is loaded by
    reference from another project.

EXAMPLES
  project entry --config=External --version=1.0.0 --repo=http://ss3.gemtalksystems.com/ss/external \
               --loads=`#('Core')` /home/external

  project entry --baseline=External --repo=github://dalehenrich/external:master/repository \
               --loads=`#('Core')` /home/external

  project entry --git=projectHome --repo=$GS_HOME /home/external

  NOTE - use the `tode it` menu item to run the examples directly from this window.

SEE ALSO
  browse class --exact --hier TDProjectEntryDefinition
  "The Metacello Lock Command Reference" [1]

[1] https://github.com/dalehenrich/metacello-work/blob/master/docs/LockCommandReference.md#lock-command-reference
  NOTE - use the `tode it` menu item to run the commands directly from this window.
```

###*project load* man page
```
NAME
  project load - Load the Metacello project

SYNOPSIS
  project load [--loads=<load-expression>]
               [--className=<project-class-name]
               [--no-flush] [--no-get]
               [ (--baseline | --configuration --version=<version> ) ]
               [--repository=<repository-reference>]
               [--onConflict=useNew|useExisting]
               [--onDowngrade=useNew|useExisting]
               [--onLock=break|honor]
               [--onUpgrade=useNew|useExisting]
               [--ignoreImage] [--silently]
               [--cacheRepository=@<repository-reference>]
               [--repositoryOverrides=@<repository-reference>]
               [--deploy=auto|bulk|none]
               ( <project-name> | @<project-reference> )

DESCRIPTION
  Defaults:
    deploy      - bulk
    onConflict  - useNew
    onLock      - honor
    onDowngrade - useNew
    onUpgrade   - useNew

EXAMPLES
  project load Seaside3

  NOTE - use the `tode it` menu item to run the examples directly from this window.

SEE ALSO
  


  NOTE - use the `tode it` menu item to run the commands directly from this window.
```
###tODE `example` script
```Smalltalk
[ :topez :objIn :tokens :command :commandNode | 
  | opts args |
  "for help: ./example -h"
  command
    getOptsMixedLongShort:
      {#('help' $h #'none').
      #('clear' nil #'none').
      #('client' nil #'required').
      #('model' nil #'required').
      #('register' nil #'required').
      #('reset' nil #'none').
      #('restart' nil #'required').
      #('server' nil #'required').
      #('start' nil #'required').
      #('status' nil #'required').
      #('stop' nil #'required').
      #('trace' nil #'none').
      #('unregister' nil #'required')}
    optionsAndArguments: [ :options :operands | 
      opts := options.
      args := operands ].
  opts
    at: 'help'
    ifAbsent: [ 
      | result gemServer trace transModel |
      trace := false.
      opts
        at: 'clear'
        ifPresent: [ :ignored | topez evaluateCommandString: 'ol clear --age=`1 hour`' ].
      opts
        at: 'reset'
        ifPresent: [ :ignored | result := GemServerRemoteTaskExample reset ].
      opts at: 'trace' ifPresent: [ :ignored | trace := true ].
      opts at: 'model' ifPresent: [ :model | transModel := model ].
      opts
        at: 'unregister'
        ifPresent: [ :serverName | result := GemServerRegistry removeGemServerNamed: serverName ]
        ifAbsent: [ 
          | serverName serverCls |
          opts
            at: 'register'
            ifPresent: [ :serverNameArg | serverName := serverNameArg ].
          transModel = 'A'
            ifTrue: [ serverCls := GemServerRemoteServerTransactionModelAExample ]
            ifFalse: [ 
              transModel = 'B'
                ifTrue: [ serverCls := GemServerRemoteServerTransactionModelBExample ] ].
          serverName
            ifNotNil: [ 
              gemServer := (GemServerRegistry gemServerNamed: serverName)
                ifNil: [ 
                  gemServer := (serverCls register: serverName)
                    tracing: trace;
                    interactiveMode: true;
                    yourself ] ].
          result := gemServer ].
      opts
        at: 'client'
        ifPresent: [ :taskName | 
          | selectors client task |
          selectors := Dictionary new
            at: 'break' put: #'scheduleBreakpointTask';
            at: 'error' put: #'scheduleErrorTask';
            at: 'http' put: #'scheduleExampleHttpTask';
            at: 'fast' put: #'scheduleFastTask';
            at: 'halt' put: #'scheduleHaltTask';
            at: 'serverError' put: #'scheduleInternalServerError';
            at: 'oomPersistent' put: #'scheduleOutOfMemoryPersistent';
            at: 'oomTemp' put: #'scheduleOutOfMemoryTemp';
            at: 'simple' put: #'scheduleSimpleTask';
            at: 'status' put: #'scheduleStatusTask';
            at: 'overflow' put: #'scheduleStackOverflow';
            at: 'time' put: #'scheduleTimeInLondonTask';
            at: 'warning' put: #'scheduleWarning';
            yourself.
          opts
            at: 'server'
            ifPresent: [ :serverName | 
              client := (gemServer := GemServerRegistry gemServerNamed: serverName)
                clientClass new ].
          task := client perform: (selectors at: taskName).
          task label: taskName.
          client doCommitTransaction.
          result := client waitForTasks: {task} gemServer: gemServer ].
      opts
        at: 'stop'
        ifPresent: [ :serverName | result := (GemServerRegistry gemServerNamed: serverName) stop ].
      opts
        at: 'start'
        ifPresent: [ :serverName | result := (GemServerRegistry gemServerNamed: serverName) start ].
      opts
        at: 'status'
        ifPresent: [ :serverName | result := (GemServerRegistry gemServerNamed: serverName) status ].
      opts
        at: 'restart'
        ifPresent: [ :serverName | result := (GemServerRegistry gemServerNamed: serverName) restart ].
      result ]
    ifPresent: [ :ignored | 
      TDManPage
        viewManPage:
          'NAME
  example - example sript utility template
SYNOPSIS
  example [-h|--help]
  example --register=<server-name> --model=[A|B] [--trace]
  example --register=<server-name> --model=[A|B] [--trace]
  example --unregister=<server-name>
  example --reset
  example --start=<server-name>
  example --restart=<server-name>
  example --stop=<server-name>
  example --status=<server-name>
  example --clear
  example --client=[break|error|http|fast|halt|serverError|oomPersistent|oomTemp|simple|status|overflow|time|warning] \
         --server=<server-name>  [--trace]
DESCRIPTION
EXAMPLES
  ./example --help
  ./example -h

  ./example --register=example
  ./example --register=example --model=A --trace
  ./example --register=example --model=B --trace
  ./example --unregister=example
  ./example --reset

  ./example --start=example
  ./example --stop=example
  ./example --restart=example
  ./example --status=example

  ./example --clear

  ./example --client=break --server=example --trace
  ./example --client=error --server=example --trace
  ./example --client=http --server=example --trace
  ./example --client=fast --server=example --trace
  ./example --client=halt --server=example --trace
  ./example --client=serverError --server=example --trace
  ./example --client=oomPersistent --server=example --trace
  ./example --client=oomTemp --server=example --trace
  ./example --client=simple --server=example --trace
  ./example --client=status --server=example --trace
  ./example --client=overflow --server=example --trace
  ./example --client=time --server=example --trace
  ./example --client=warning --server=example --trace
'
        topez: topez ] ]
```

###tODE `example` script man page
```
NAME
  example - example sript utility template

SYNOPSIS
  example [-h|--help]
  example --register=<server-name> --model=[A|B] [--trace]
  example --register=<server-name> --model=[A|B] [--trace]
  example --unregister=<server-name>
  example --reset
  example --start=<server-name>
  example --restart=<server-name>
  example --stop=<server-name>
  example --status=<server-name>
  example --clear
  example --client=[break|error|http|fast|halt|serverError|oomPersistent|oomTemp|simple|status|overflow|time|warning] \
         --server=<server-name>  [--trace]

DESCRIPTION
  

EXAMPLES
  ./example --help
  ./example -h

  ./example --register=example
  ./example --register=example --model=A --trace
  ./example --register=example --model=B --trace
  ./example --unregister=example
  ./example --reset

  ./example --start=example
  ./example --stop=example
  ./example --restart=example
  ./example --status=example

  ./example --clear

  ./example --client=break --server=example --trace
  ./example --client=error --server=example --trace
  ./example --client=http --server=example --trace
  ./example --client=fast --server=example --trace
  ./example --client=halt --server=example --trace
  ./example --client=serverError --server=example --trace
  ./example --client=oomPersistent --server=example --trace
  ./example --client=oomTemp --server=example --trace
  ./example --client=simple --server=example --trace
  ./example --client=status --server=example --trace
  ./example --client=overflow --server=example --trace
  ./example --client=time --server=example --trace
  ./example --client=warning --server=example --trace

  NOTE - use the `tode it` menu item to run the examples directly from this window.
```

---

[1]: http://downloads.gemtalksystems.com/docs/GemStone64/3.2.x/GS64-GemBuilderforC-3.2.pdf