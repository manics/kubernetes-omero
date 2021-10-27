#!/usr/bin/env python3
"""
Automate building and publishing helm charts and associated images.

This is used as part of the JupyterHub and Binder projects.
"""

"""
BSD 3-Clause License

Copyright (c) 2018, Project Jupyter Contributors
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
"""

import argparse
from collections.abc import MutableMapping
from functools import lru_cache, partial
import os
import pipes
import shutil
import subprocess
from tempfile import TemporaryDirectory

import docker
from ruamel.yaml import YAML
from ruamel.yaml.scalarstring import SingleQuotedScalarString

__version__ = "0.3.2.dev"

# name of the environment variable with GitHub token
GITHUB_TOKEN_KEY = "GITHUB_TOKEN"
# name of the environment variable with GitHub user
GITHUB_ACTOR_KEY = "GITHUB_ACTOR"

# name of possible repository keys used in image value
IMAGE_REPOSITORY_KEYS = {"name", "repository"}

# use safe roundtrip yaml loader
yaml = YAML(typ="rt")
yaml.preserve_quotes = True  ## avoid mangling of quotes
yaml.indent(mapping=2, offset=2, sequence=4)


def run_cmd(call, cmd, *, echo=True, **kwargs):
    """Run a command and echo it first"""
    if echo:
        print("$> " + " ".join(map(pipes.quote, cmd)))
    return call(cmd, **kwargs)


check_call = partial(run_cmd, subprocess.check_call)
check_output = partial(run_cmd, subprocess.check_output)


def git_remote(git_repo):
    """Return the URL for remote git repository.

    Depending on the system setup it returns ssh or https remote.
    """
    github_token = os.getenv(GITHUB_TOKEN_KEY)
    github_actor = os.getenv(GITHUB_ACTOR_KEY, "")
    if github_token:
        repo = git_repo + ("" if git_repo.endswith(".git") else ".git")
        return f"https://{github_actor}:{github_token}@github.com/{repo}"
    return "git@github.com:{0}".format(git_repo)


def last_modified_commit(*paths, **kwargs):
    """Get the last commit to modify the given paths"""
    return check_output(
        ["git", "log", "-n", "1", "--pretty=format:%h", "--", *paths], **kwargs
    ).decode("utf-8")


def list_git_tags():
    """Get the list of git tags"""
    tags = (
        check_output(
            [
                "git",
                "tag",
            ]
        )
        .decode("utf-8")
        .split()
    )
    return set(tags)


def last_modified_date(*paths, **kwargs):
    """Return the last modified date (as a string) for the given paths"""
    return check_output(
        ["git", "log", "-n", "1", "--pretty=format:%cd", "--date=iso", "--", *paths],
        **kwargs,
    ).decode("utf-8")


def path_touched(*paths, commit_range):
    """Return whether the given paths have been changed in the commit range

    Used to determine if a build is necessary

    Args:
    *paths (str):
        paths to check for changes
    commit_range (str):
        range of commits to check if paths have changed
    """
    return (
        check_output(["git", "diff", "--name-only", commit_range, "--", *paths])
        .decode("utf-8")
        .strip()
        != ""
    )


def render_build_args(options, ns):
    """Get docker build args dict, rendering any templated args.

    Args:
    options (dict):
        The dictionary for a given image from chartpress.yaml.
        Fields in `options['buildArgs']` will be rendered and returned,
        if defined.
    ns (dict): the namespace used when rendering templated arguments
    """
    build_args = options.get("buildArgs", {})
    for key, value in build_args.items():
        build_args[key] = value.format(**ns)
    return build_args


def build_image(
    image_path, image_name, build_args=None, dockerfile_path=None, image_aliases=[]
):
    """Build an image

    Args:
    image_path (str): the path to the image directory
    image_name (str): image 'name:tag' to build
    build_args (dict, optional): dict of docker build arguments
    dockerfile_path (str, optional):
        path to dockerfile relative to image_path
        if not `image_path/Dockerfile`.
    image_aliases (list(str), optional):
        list of additional 'name:tag' image aliases
    """
    cmd = ["docker", "build", "-t", image_name, image_path]
    if dockerfile_path:
        cmd.extend(["-f", dockerfile_path])

    for k, v in (build_args or {}).items():
        cmd += ["--build-arg", "{}={}".format(k, v)]
    check_call(cmd)
    for alias in image_aliases:
        check_call(["docker", "tag", image_name, alias])


@lru_cache()
def docker_client():
    """Cached getter for docker client"""
    return docker.from_env()


@lru_cache()
def image_needs_pushing(image):
    """Return whether an image needs pushing

    Args:

    image (str): the `repository:tag` image to be build.

    Returns:

    True: if image needs to be pushed (not on registry)
    False: if not (already present on registry)
    """
    d = docker_client()
    try:
        d.images.get_registry_data(image)
    except docker.errors.APIError:
        # image not found on registry, needs pushing
        return True
    else:
        return False


@lru_cache()
def image_needs_building(image):
    """Return whether an image needs building

    Checks if the image exists (ignores commit range),
    either locally or on the registry.

    Args:

    image (str): the `repository:tag` image to be build.

    Returns:

    True: if image needs to be built
    False: if not (image already exists)
    """
    d = docker_client()

    # first, check for locally built image
    try:
        d.images.get(image)
    except docker.errors.ImageNotFound:
        # image not found, check registry
        pass
    else:
        # it exists locally, no need to check remote
        return False

    # image may need building if it's not on the registry
    return image_needs_pushing(image)


def build_images(
    prefix,
    images,
    tag=None,
    commit_range=None,
    push=False,
    chart_version=None,
    skip_build=False,
    tag_prefix="",
    tag_latest=False,
):
    """Build a collection of docker images

    Args:
    prefix (str): the prefix to add to images
    images (dict): dict of image-specs from chartpress.yml
    tag (str):
        Specific tag to use instead of the last modified commit.
        If unspecified the tag for each image will be the hash of the last commit
        to modify the image's files.
    commit_range (str):
        The range of commits to consider, e.g. for building in CI.
        If an image hasn't changed in the given range,
        it will not be rebuilt.
    push (bool):
        Whether to push the resulting images (default: False).
    chart_version (str):
        The chart version, included as a prefix on image tags
        if `tag` is not specified.
    skip_build (bool):
        Whether to skip the actual image build (only updates tags).
    tag_prefix (str):
        An optional prefix on all image tags (in front of chart_version or tag)
    tag_latest (bool):
        Whether to also tag images with the latest tag
    """
    value_modifications = {}
    for name, options in images.items():
        image_path = options.get("contextPath", os.path.join("images", name))
        image_tag = tag
        # include chartpress.yaml itself as it can contain build args and
        # similar that influence the image that would be built
        paths = list(options.get("paths", [])) + [image_path, "chartpress.yaml"]
        last_commit = last_modified_commit(*paths)
        if tag is None:
            if chart_version:
                image_tag = "{}-{}".format(chart_version, last_commit)
            else:
                image_tag = last_commit
        image_name = prefix + name
        image_tag = tag_prefix + image_tag
        image_spec = "{}:{}".format(image_name, image_tag)

        image_aliases = []
        if tag_latest:
            image_aliases = ["{}:latest".format(image_name)]

        value_modifications[options["valuesPath"]] = {
            "repository": image_name,
            "tag": SingleQuotedScalarString(image_tag),
        }

        if skip_build:
            continue

        template_namespace = {
            "LAST_COMMIT": last_commit,
            "TAG": image_tag,
        }

        if tag or image_needs_building(image_spec):
            build_args = render_build_args(options, template_namespace)
            build_image(
                image_path,
                image_spec,
                build_args,
                options.get("dockerfilePath"),
                image_aliases,
            )
        else:
            print(f"Skipping build for {image_spec}, it already exists")

        if push:
            if tag or image_needs_pushing(image_spec):
                check_call(["docker", "push", image_spec])
                for alias in image_aliases:
                    check_call(["docker", "push", alias])
            else:
                print(f"Skipping push for {image_spec}, already on registry")
    return value_modifications


def build_values(name, values_mods):
    """Update name/values.yaml with modifications"""
    values_file = os.path.join(name, "values.yaml")

    with open(values_file) as f:
        values = yaml.load(f)

    for key, value in values_mods.items():
        parts = key.split(".")
        mod_obj = values
        for p in parts:
            mod_obj = mod_obj[p]
        print(f"Updating {values_file}: {key}: {value}")

        if isinstance(mod_obj, MutableMapping):
            keys = IMAGE_REPOSITORY_KEYS & mod_obj.keys()
            if keys:
                for key in keys:
                    mod_obj[key] = value["repository"]
            else:
                possible_keys = " or ".join(IMAGE_REPOSITORY_KEYS)
                raise KeyError(f"Could not find {possible_keys} in {values_file}:{key}")

            mod_obj["tag"] = value["tag"]
        else:
            raise TypeError(f"The key {key} in {values_file} must be a mapping.")

    with open(values_file, "w") as f:
        yaml.dump(values, f)


def build_chart(name, version=None, paths=None, reset=False, release=False):
    """Update chart with specified version or last-modified commit in path(s)"""
    chart_file = os.path.join(name, "Chart.yaml")
    with open(chart_file) as f:
        chart = yaml.load(f)

    if version is None:
        if paths is None:
            paths = ["."]
        commit = last_modified_commit(*paths)

        if reset:
            version = chart["version"].split("-")[0]
        elif release:
            version = chart["version"]
        else:
            version = chart["version"].split("-")[0] + "-h" + commit

    chart["version"] = version

    with open(chart_file, "w") as f:
        yaml.dump(chart, f)

    return version


def publish_pages(name, paths, git_repo, published_repo, branch, extra_message=""):
    """Publish helm chart index to github pages"""
    version = last_modified_commit(*paths)
    checkout_dir = "{}-{}".format(name, version)
    check_call(["git", "clone", "-b", branch, git_remote(git_repo), checkout_dir])

    check_call(["helm", "dependency", "update", name])

    # package the latest version into a temporary directory
    # and run helm repo index with --merge to update index.yaml
    # without refreshing all of the timestamps
    with TemporaryDirectory() as td:
        check_call(
            [
                "helm",
                "package",
                name,
                "--destination",
                td + "/",
            ]
        )

        check_call(
            [
                "helm",
                "repo",
                "index",
                td,
                "--url",
                published_repo,
                "--merge",
                os.path.join(checkout_dir, "index.yaml"),
            ]
        )

        # equivalent to `cp td/* checkout/`
        # copies new helm chart and updated index.yaml
        for f in os.listdir(td):
            shutil.copy2(os.path.join(td, f), os.path.join(checkout_dir, f))
    check_call(["git", "add", "."], cwd=checkout_dir)
    if extra_message:
        extra_message = "\n\n%s" % extra_message
    else:
        extra_message = ""
    check_call(
        [
            "git",
            "commit",
            "-m",
            "[{}] Automatic update for commit {}{}".format(
                name, version, extra_message
            ),
        ],
        cwd=checkout_dir,
    )
    check_call(
        ["git", "push", "origin", f"HEAD:{branch}"],
        cwd=checkout_dir,
    )


def main():
    """Run chartpress"""
    argparser = argparse.ArgumentParser(description=__doc__)

    argparser.add_argument(
        "--commit-range", help="Range of commits to consider when building images"
    )
    argparser.add_argument(
        "--push", action="store_true", help="Push built images to docker hub"
    )
    argparser.add_argument(
        "--publish-chart",
        action="store_true",
        help="Publish updated chart to branch (publish-branch)",
    )
    argparser.add_argument(
        "--publish-branch",
        default="gh-pages",
        help="Publish updated chart to this branch",
    )
    argparser.add_argument(
        "--tag", default=None, help="Use this tag for images & charts"
    )
    argparser.add_argument(
        "--tag-latest",
        action="store_true",
        help="Also tag Docker images with latest tag",
    )
    argparser.add_argument(
        "--git-release",
        action="store_true",
        help="Only run if no matching git tag, use the unmodified chart version, git tag repository. Handle charts independently.",
    )
    argparser.add_argument(
        "--git-push", action="store_true", help="If a git tag was created push it."
    )
    argparser.add_argument(
        "--extra-message",
        default="",
        help="Extra message to add to the commit message when publishing charts",
    )
    argparser.add_argument(
        "--image-prefix", default=None, help="Override image prefix with this value"
    )
    argparser.add_argument("--reset", action="store_true", help="Reset image tags")
    argparser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip image build, only render the charts",
    )

    args = argparser.parse_args()

    with open("chartpress.yaml") as f:
        config = yaml.load(f)

    if args.git_release:
        git_tags = list_git_tags()
        git_tags_to_create = set()

    for chart in config["charts"]:
        chart_paths = ["."] + list(chart.get("paths", []))

        version = args.tag
        if version:
            # version of the chart shouldn't have leading 'v' prefix
            # if tag is of the form 'v1.2.3'
            version = version.lstrip("v")
        chart_version = build_chart(
            chart["name"],
            paths=chart_paths,
            version=version,
            reset=args.reset,
            release=args.git_release,
        )
        expected_tag = "{}{}".format(chart.get("gitTagPrefix", ""), chart_version)

        if args.git_release:
            # Only build and publish if this version hasn't been git tagged
            if expected_tag in git_tags:
                print(
                    f"Git tag {expected_tag} already exists, skipping chart {chart['name']}"
                )
                continue
            else:
                git_tags_to_create.add(expected_tag)

        if "images" in chart:
            image_prefix = (
                args.image_prefix
                if args.image_prefix is not None
                else chart["imagePrefix"]
            )
            tag = args.tag
            if args.git_release:
                tag = chart_version
            elif args.reset:
                tag = (chart.get("resetTag", "set-by-chartpress"),)
            value_mods = build_images(
                prefix=image_prefix,
                images=chart["images"],
                tag=tag,
                commit_range=args.commit_range,
                push=args.push,
                # exclude `-<hash>` from chart_version prefix for images
                chart_version=chart_version.split("-", 1)[0],
                skip_build=args.skip_build or args.reset,
                tag_prefix=chart.get("imageTagPrefix", ""),
                tag_latest=args.tag_latest,
            )
            build_values(chart["name"], value_mods)

        if args.publish_chart:
            publish_pages(
                chart["name"],
                paths=chart_paths,
                git_repo=chart["repo"]["git"],
                published_repo=chart["repo"]["published"],
                branch=args.publish_branch,
                extra_message=args.extra_message,
            )

    if args.git_release and git_tags_to_create:
        # Tag as the last step after everything else succeeded
        modified = check_output(["git", "diff", "HEAD"]).strip()
        if modified:
            # Don't modify current branch
            current = check_output(["git", "rev-parse", "HEAD"]).decode().strip()
            check_call(["git", "checkout", current])
            msg = "[{}] Automatic update for tag".format(",".join(git_tags_to_create))
            check_call(["git", "commit", "-am", msg])
        for tag in git_tags_to_create:
            check_call(["git", "tag", tag])
            if args.git_push:
                check_call(["git", "push", "origin", tag])


if __name__ == "__main__":
    main()
