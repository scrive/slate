let BackendWorkflow = ../lib/backend-workflow.dhall

let Step = ../type/Step.dhall
let Job = ../type/Job.dhall
let Workflow = ../type/Workflow.dhall
let NixShell = ../type/NixShell.dhall
let GHCVersion = ../type/GHCVersion.dhall

in
BackendWorkflow.createWorkflow
  BackendWorkflow.Args ::
  { name = "GHC 8.6 Backend Tests (Nix)"
  , ghcVersion = GHCVersion.Type.ghc86
  , nixShell = NixShell.Type.dev-shell-optimized
  , runsOn =
      [ Job.RunsOn.ubuntu-latest
      ]
  , triggers = Workflow.Triggers ::
      { push = Some
          { branches = Some [ "master" ]
          }
      }
  }
