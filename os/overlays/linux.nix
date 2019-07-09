{ stdenv, buildPackages, fetchFromGitHub, perl, buildLinux, modDirVersionArg ? null, ... } @ args:

with stdenv.lib;

buildLinux (args // rec {
  version = "5.2.0";
  modDirVersion = "5.2.0";

  src = fetchFromGitHub {
    owner = "vpsfreecz";
    repo = "linux";
    rev = "2117720f1af0eb7e992a39c15d82230efa6002da";
    sha256 = "16y3sd43w35iz4py7ixrlxva4nxg0ypfyyfr8raxhpna4a2y5121";
  };

} // (args.argsOverride or {}))
