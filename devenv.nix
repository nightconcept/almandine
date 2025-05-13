{
  pkgs,
  inputs,
  ...
}:{
  packages = with pkgs; [
    gocyclo
    golangci-lint
    go-task
    pre-commit
    shellcheck
  ];

  languages.go = {
    enable = true;
  };
  languages.python = {
    enable = true;
    venv.enable = true;
    venv.requirements = ''
      gitingest
      requests
      python-gnupg
      semver
    '';
  };

  enterShell = ''
    # Ensure pre-commit hook is installed/updated on direnv/devenv entry
    if [ -d .git ]; then
      pre-commit install --install-hooks --overwrite || true
    fi
  '';
}
