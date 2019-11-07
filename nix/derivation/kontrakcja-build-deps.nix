{
  nixpkgs
, inHaskellPackages
}:
let
  inherit (nixpkgs) pkgs;

  callPackage = self: name: src:
    self.callCabal2nix
      name
      src
      {}
  ;

  callScrivePackage = self: name: version:
    callPackage self
        name
        (builtins.fetchTarball
          "http://hackage.scrive.com/package/${name}-${version}.tar.gz")
    ;

  callGitPackage = self: name: url: rev:
    callPackage self
        name
        (builtins.fetchGit {
          inherit url rev;
        })
      ;

  logSrc = builtins.fetchGit {
    url = "ssh://git@github.com/scrive/log.git";
    rev = "27bbb54abed66e65fccfb890e887146cc3a197a0";
  };

  haskellLib = pkgs.haskell.lib;

  haskellPackages = inHaskellPackages.override (old: {
    # Use composeExtensions to prevent Nix from obscurely
    # drop any previous overrides
    overrides = pkgs.lib.composeExtensions
      (old.overrides or (_: _: {}))
      (self: super: {

        # Take Scrive Haskell packages directly from GitHub.
        hpqtypes = haskellLib.dontCheck
          (
            callGitPackage super
            "hpqtypes"
            "ssh://git@github.com/scrive/hpqtypes.git"
            "be71b0c49740018748df482c9fc3f1a17b5e1655"
          )
        ;

        hpqtypes-extras = haskellLib.dontCheck
          (haskellLib.dontHaddock
            (callGitPackage super
              "hpqtypes-extras"
              "ssh://git@github.com/scrive/hpqtypes-extras.git"
              "8adfa1315987544369899e8c4c62823799c92047"
            ))
        ;

        consumers = haskellLib.dontCheck
          (callGitPackage super
            "consumers"
            "ssh://git@github.com/scrive/consumers.git"
            "8b1a2cd4642dd910a8116234a82dd2c3ff1e027d"
          )
        ;

        fields-json = callGitPackage super
          "fields-json"
          "git@github.com:scrive/fields-json.git"
          "c6d850b24e7d58dd24d95e8676d12ce35155dd4d"
        ;

        resource-pool = callScrivePackage super
          "resource-pool"
          "0.2.3.2.1"
        ;

        unjson = haskellLib.dontCheck
          (super.callHackage
            "unjson"
            "0.15.2.1"
            {})
        ;

        kontrakcja-templates = callScrivePackage super
          "kontrakcja-templates"
          "0.10"
        ;

        log-base = callPackage super "log-base"
          (logSrc + "/log-base");

        log-postgres = callPackage super "log-postgres"
          (logSrc + "/log-postgres");

        log-elasticsearch = callPackage super "log-elasticsearch"
          (logSrc + "/log-elasticsearch");

        mixpanel = haskellLib.appendPatch
          (
            callGitPackage super
            "mixpanel"
            "ssh://git@github.com/scrive/mixpanel.git"
            "d6c378d738f936d7f7950ee278d955726c255535"
          )
          ../patches/mixpanel.patch
        ;

        brittany = callGitPackage super
          "brittany"
          "ssh://git@github.com/lspitzner/brittany.git"
          "38f77f6c5e04883dcbda60286ce88e83275009ab"
        ;

        # bloodhound has not updated their dependencies on http-client
        # and containers major version for ages. Remove this when
        # it is fixed in new releases.
        bloodhound = haskellLib.dontCheck
          (haskellLib.appendPatch
            (callGitPackage super
              "bloodhound"
              "ssh://git@github.com/bitemyapp/bloodhound.git"
              "4c743e1082b8b5eec53a7155733999441be0efce"
            )
            ../patches/bloodhound.cabal.patch
          )
        ;
      });
  });
in
haskellPackages
