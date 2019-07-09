{ mkDerivation, attoparsec, base, bytestring, containers, fetchgit
, hspec, raw-strings-qq, stdenv, transformers
}:
mkDerivation {
  pname = "data-prometheus";
  version = "0.1.0.0";
  src = fetchgit {
    url = "https://github.com/vpsfreecz/data-prometheus";
    sha256 = "124la8ai3f1ifn218kasnrdhgq2n2rw7kwm5dq8n5b95vnlg5916";
    rev = "fce44551e21d3b150be1c10bc1136af17faa0f28";
    fetchSubmodules = true;
  };
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    attoparsec base bytestring containers transformers
  ];
  testHaskellDepends = [
    attoparsec base containers hspec raw-strings-qq
  ];
  homepage = "https://github.com/vpsfreecz/data-prometheus";
  description = "Prometheus metrics data types and parser";
  license = stdenv.lib.licenses.bsd3;
}
