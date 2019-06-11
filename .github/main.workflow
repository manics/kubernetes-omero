workflow "Publish chart" {
  on = "push"
  resolves = ["Chartpress"]
}

action "Master only" {
  uses = "actions/bin/filter@3c0b4f0e63ea54ea5df2914b4fabf383368cd0da"
  args = "branch master"
}

action "Not deleted" {
  uses = "actions/bin/filter@3c0b4f0e63ea54ea5df2914b4fabf383368cd0da"
  needs = ["Master only"]
  args = "not deleted"
}

action "Wait for Travis" {
  uses = "manics/test-actions/wait-for-travis@master"
  needs = ["Not deleted"]
}

action "Docker login" {
  uses = "actions/docker/login@8cdf801b322af5f369e00d85e9cf3a7122f49108"
  needs = ["Wait for Travis"]
  secrets = ["DOCKER_USERNAME", "DOCKER_PASSWORD"]
}

action "Chartpress" {
  uses = "manics/chartpress@devel"
  needs = ["Docker login"]
  args = "--git-release --tag-latest --push --publish-chart --git-push"
  secrets = ["GITHUB_TOKEN"]
}
