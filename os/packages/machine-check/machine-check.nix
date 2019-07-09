{ mkDerivation, atomic-write, attoparsec, base, bytestring
, config-ini, containers, data-prometheus, dns, fetchgit, hspec
, iproute, pretty-simple, process, stdenv, text
}:
mkDerivation {
  pname = "machine-check";
  version = "0.1.0.0";
  src = fetchgit {
    url = "https://github.com/vpsfreecz/machine-check";
    sha256 = "1iqmryl1fbjnl14c8hll7x7jnj7c1z9648yxlnwc6v9ylz09iapd";
    rev = "45f824f84776cb9bda42075238594a5f6fce6a83";
    fetchSubmodules = true;
  };
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    atomic-write attoparsec base bytestring config-ini containers
    data-prometheus dns iproute pretty-simple process text
  ];
  executableHaskellDepends = [ base bytestring pretty-simple ];
  testHaskellDepends = [ attoparsec base hspec text ];
  homepage = "https://github.com/vpsfreecz/machine-check";
  description = "Linux system checks";
  license = stdenv.lib.licenses.bsd3;
}
