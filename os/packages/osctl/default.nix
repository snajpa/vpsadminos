{ pkgs, lib, bundlerApp }:

bundlerApp {
  pname = "osctl";
  gemdir = ./.;
  exes = [ "osctl" "ct" "group" "healthcheck" "pool" "repo" "user" ];
  manpages = [ "man8/osctl.8" ];
  postBuild = ''
    mkdir -p $out/share/bash-completion/completions $out/etc
    ln -sf $out/share/bash-completion/completions $out/etc/bash_completion.d
    $out/bin/osctl gen-completion bash > $out/share/bash-completion/completions/osctl
  '';

  meta = with lib; {
    description = "";
    homepage    = https://github.com/vpsfreecz/vpsadmin;
    license     = licenses.gpl3;
    maintainers = [ maintainers.sorki ];
    platforms   = platforms.unix;
  };
}
