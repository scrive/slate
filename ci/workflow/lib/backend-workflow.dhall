let Step = ../type/Step.dhall
let Job = ../type/Job.dhall
let Workflow = ../type/Workflow.dhall
let GHCVersion = ../type/GHCVersion.dhall
let NixShell = ../type/NixShell.dhall
let CreateJob = ./create-job.dhall

let Args =
  { Type =
      { name: Text
      , ghcVersion: GHCVersion.Type
      , nixShell: NixShell.Type
      , testFrontend: Bool
      , cacheCabal: Bool
      , runsOn: List Job.RunsOn
      , triggers: Workflow.Triggers.Type
      }
  , default =
      { ghcVersion = GHCVersion.Type.ghc88
      , nixShell = NixShell.Type.dev-shell-optimized
      , testFrontend = False
      , cacheCabal = False
      }
  }

let createWorkflow =
  \(args: Args.Type) ->
    let inArgs =
      { ghcVersion = args.ghcVersion
      , nixShell = args.nixShell
      , runsOn = args.runsOn
      , nixExtraArgs = None Text
      }

    let cacheCabalSteps =
      if args.cacheCabal
      then \(name: Text) ->
          [ Step ::
            { name = "Cache ~/.cabal"
            , uses = Some "actions/cache@v2"
            , with = Some toMap
              { path = "~/.cabal"
              , key = "\${{ runner.os }}-cabal-${name}-\${{ hashFiles('**/*.cabal') }}"
              , restore-keys = ''
                ''${{ runner.os }}-cabal-${name}-''${{ hashFiles('**/*.cabal') }}
                ''${{ runner.os }}-cabal-${name}-
                ''
              }
            }
          ]
      else \(name: Text) -> ([] : List Step.Type)

    let createJob = \(name: Text) -> \(steps: List Step.Type) ->
      CreateJob.createJob
        ( inArgs // { steps = cacheCabalSteps name # steps } )

    let backendTests1 =
      [ Step ::
        { name = "Run Backend Tests"
        , timeout-minutes = Some 180
        , run = Some "./ci/scripts/run-backend-tests.sh"
        , env = Some toMap
            { PDFTOOLS_CONFIG = "\${{ secrets.PDFTOOLS_CONFIG }}"
            }
        }
      ]

    let backendTests2 : List Step.Type =
      if args.testFrontend
      then
        backendTests1 #
        [ Step ::
          { name = "Test Frontend"
          , run = Some "./ci/scripts/run-frontend-tests.sh"
          }
        ]
      else backendTests1

    let backendTests = CreateJob.createJob
      ( inArgs //
          { steps = cacheCabalSteps "backend-tests" # backendTests2
          , nixExtraArgs = if args.testFrontend
              then Some "--arg extra-run-deps 'pkgs: hsPkgs: [ pkgs.chromium ]'"
              else None Text
          }
      )

    let formatting = createJob "test-formatting"
      [ Step ::
        { name = "Test Formatting"
        , run = Some "./shake.sh test-formatting"
        }
      ]

    let hlint = createJob "hlint"
      [ Step ::
        { name = "Test HLint"
        , run = Some "./shake.sh hlint"
        }
      ]

    let detect-unused = createJob "detect-unused"
      [ Step ::
        { name = "Detect Old Templates"
        , run = Some "./shake.sh detect-old-templates"
        }
      , Step ::
        { name = "Detect Old Localizations"
        , run = Some "./shake.sh detect-old-localizations"
        }
      ]

    let jobs =
      { backend-tests = backendTests
      , formatting = formatting
      , hlint = hlint
      , detect-unused = detect-unused
      }

    in
    Workflow.Workflow ::
      { name = args.name
      , on = Some args.triggers
      , jobs = toMap jobs
      }
in
{ Args = Args
, createWorkflow = createWorkflow
}
