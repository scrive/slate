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
      , nixExtraArgs: Optional Text
      , runsOn: List Job.RunsOn
      , triggers: Workflow.Triggers.Type
      }
  , default =
      { ghcVersion = GHCVersion.Type.ghc88
      , nixShell = NixShell.Type.dev-shell-optimized
      , nixExtraArgs = None Text
      }
  }

let createWorkflow =
  \(args: Args.Type) ->
    let inArgs =
      { ghcVersion = args.ghcVersion
      , nixShell = args.nixShell
      , nixExtraArgs = args.nixExtraArgs
      , runsOn = args.runsOn
      }

    let createJob = \(finalStep: Step.Type) ->
      CreateJob.createJob
        ( inArgs // { finalStep = finalStep } )

    let backendTests = createJob
      Step ::
        { name = "Run Backend Tests"
        , timeout-minutes = Some 60
        , run = Some "./ci/scripts/run-backend-tests.sh"
        , env = Some toMap
            { PDFTOOLS_CONFIG = "\${{ secrets.PDFTOOLS_CONFIG }}"
            }
        }

    let formatting = createJob
      Step ::
        { name = "Test Formatting"
        , run = Some "./shake.sh test-formatting"
        }

    let hlint = createJob
      Step ::
        { name = "Test HLint"
        , run = Some "./shake.sh hlint"
        }


    let detect-unused = createJob
      Step ::
        { name = "Detect Unused"
        , run = Some ''
            ./shake.sh detect-old-templates
            ./shake.sh detect-old-localizations
            ''
        }
    in
    Workflow.Workflow ::
      { name = args.name
      , on = Some args.triggers
      , jobs = toMap
          { backend-tests = backendTests
          , formatting = formatting
          , hlint = hlint
          }
      }
in
{ Args = Args
, createWorkflow = createWorkflow
}
