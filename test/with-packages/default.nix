{ stdenv, lib, numactl, util, mkPkgSet, recurseIntoAttrs, testSrc }:

with lib;
with util;

let
  pkgs = import ./pkgs.nix;
  pkgSet = doExactConfig: mkPkgSet {
    # generated with:
    #   cabal new-build
    #   plan-to-nix -o .
    pkg-def = pkgs.pkgs;
    pkg-def-extras = [ pkgs.extras ];
    modules = pkgs.modules ++ [
      # overrides to fix the build
      {
        packages.transformers-compat.components.library.doExactConfig = true;
      }

      # vary component config for tests
      {
        packages.test-with-packages.components.library.doExactConfig = doExactConfig;
      }
    ];
  };

  packages = doExactConfig: (pkgSet doExactConfig).config.hsPkgs;

  package = doExactConfig: (packages doExactConfig).test-with-packages;

  decLibrary = (package true).components.library;
  library = (package false).components.library;

  pkgId = p: "${p.identifier.name}-${p.identifier.version}";
  showDepends = component: concatMapStringsSep " " pkgId (component.depends or []);
  extraFlags = if stdenv.isLinux then "-L${numactl}/lib" else "";

in recurseIntoAttrs {
  # Used for testing externally with nix-shell (../tests.sh).
  # This just adds cabal-install to the existing shells.
  test-shell = addCabalInstall library;

  # A variant of test-shell with the component option doExactConfig enabled
  test-shell-dec = addCabalInstall decLibrary;

  run = stdenv.mkDerivation {
    name = "with-packages-test";
    decLibraryDepends = showDepends (pkgSet true).config.packages.test-with-packages.components.library;
    libraryDepends = showDepends (pkgSet false).config.packages.test-with-packages.components.library;

    src = ./.;

    buildPhase = ''
      ########################################################################
      # test with-packages

      printf "checking component depends ... " >& 2
      if [ -n "$decLibraryDepends" -a "$decLibraryDepends" = "$libraryDepends" ]; then
        echo "PASS" >& 2
      else
        echo "FAIL" >& 2
        echo "decLibraryDepends = $decLibraryDepends"
        echo "libraryDepends = $libraryDepends"
        exit 1
      fi

      printf "checking that the 'library' without doExactConfig works... " >& 2
      echo ${library} >& 2

      printf "checking that the 'library' with doExactConfig works... " >& 2
      echo ${decLibrary} >& 2
    '' + (if stdenv.hostPlatform.isWindows || stdenv.hostPlatform.isGhcjs
      then ''
        printf "runghc tests are not working yet for windows or ghcjs. skipping. " >& 2
      ''
      else ''
        echo "checking that non doExactConfig library.env has the dependencies... "
        echo "with runghc"
        ${library.env}/bin/${library.env.targetPrefix}runghc ./Point.hs
        echo "with ghc"
        ${library.env}/bin/${library.env.targetPrefix}ghc ${toString extraFlags} Point.hs 1> /dev/null
        ./Point

        echo "checking that doExactConfig library.env has the dependencies... "
        echo "with runghc"
        ${decLibrary.env}/bin/${decLibrary.env.targetPrefix}runghc ./Point.hs
        echo "with ghc"
        ${decLibrary.env}/bin/${decLibrary.env.targetPrefix}ghc ${extraFlags} Point.hs 1> /dev/null
        ./Point
      '') + ''
      touch $out
    '';

    dontInstall = true;

    meta = {
      platforms = platforms.all;
      disabled = stdenv.hostPlatform.isMusl;
    };

    passthru = {
      # Used for debugging with nix repl
      inherit packages pkgSet;
    };
  };
}
