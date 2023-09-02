# Used as both the install target name and package name for shortand inlining, i.e.
# `@androidsdk//install` for `@androidsdk//install:install`
_INSTALL_TARGET_NAME = "install"

# This is the name of the output "file" the install target will produce. This name is chosen to
# look nice when running. saying it is building `bazel-bin/external/androidsdk/install/sdk`.
_INSTALL_OUTPUT_NAME = "sdk"

# Relative path from the execution of `sdkmanager` to install the SDK. A path is required to force
# it to build into the `bazel-bin` directory rather than the transient `bazel-<workspace-name>`
# folder. Without it you must build the downloader repository and your target in the same build
# invocation.
_SDK_ROOT_PATH = '_'

_sdk_tools_configs = {
    "mac os x": {
        "url": "https://dl.google.com/android/repository/commandlinetools-mac-9477386_latest.zip",
        "sha256": "2072ffce4f54cdc0e6d2074d2f381e7e579b7d63e915c220b96a7db95b2900ee",
    },
    "linux": {
        "url": "https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip",
        "sha256": "bd1aa17c7ef10066949c88dc6c9c8d536be27f992a1f3b5a584f9bd2ba5646a0",
    },
    "windows": {
        "url": "https://dl.google.com/android/repository/commandlinetools-win-9477386_latest.zip",
        "sha256": "696431978daadd33a28841320659835ba8db8080a535b8f35e9e60701ab8b491",
    }
}

def _android_sdk_repository_impl(repo_ctx):
    os_name = repo_ctx.os.name.lower()
    if os_name.startswith("windows"):
        os_name = "windows"
    cfg = _sdk_tools_configs.get(os_name, None)
    if cfg == None:
        fail("Unsupported operating system: " + os_name)

    # Download Android SDK tools
    repo_ctx.download_and_extract(url = cfg["url"], sha256 = cfg["sha256"])

    # BUILD folder in the root of the generated repository
    repo_ctx.file("BUILD", content = "exports_files(['tools/bin/sdkmanager'], visibility = ['//visibility:public'])", executable = False)

    # Bazel rules file for the repository. All logic should live here
    repo_ctx.file(_INSTALL_TARGET_NAME + "/internal.bzl", content = """
def _install_sdk_impl(ctx):
    ctx.actions.write(ctx.outputs._output, '''
        {{sdkmanager}} --sdk_root='{path}' 'platforms;android-{api_level}' 'build-tools;{build_tools_version}'

    '''.format(sdkmanager = ctx.file._sdk_manager.path), is_executable = True)
    runfiles = ctx.runfiles(files = [ctx.file._sdk_manager])
    return [DefaultInfo(executable = ctx.outputs._output, runfiles = runfiles)]

install_sdk = rule(
    attrs = {{
        "_sdk_manager": attr.label(
            default = Label("//:tools/bin/sdkmanager"),
            allow_single_file = True,
            executable = True,
            cfg = "host",
        ),
    }},
    outputs = {{
        "_output": "{output_name}",
    }},
    implementation = _install_sdk_impl,
    executable = True,
)
        """.format(
        output_name = _INSTALL_OUTPUT_NAME,
        api_level = repo_ctx.attr.api_level,
        build_tools_version = repo_ctx.attr.build_tools_version,
        path = _SDK_ROOT_PATH),
    executable = False)

    # BUILD file for the single target of the repository. If the target name is the same as the
    # package, you can `bazel run` ` @repo//target` as a shorthand for `@repo//target:target`.
    repo_ctx.file(_INSTALL_TARGET_NAME + "/BUILD", content = """
load(":internal.bzl", "install_sdk")

install_sdk(
    name = "{name}",
)
    """.format(name = _INSTALL_TARGET_NAME), executable = False)

_android_sdk_repository = repository_rule(
    implementation = _android_sdk_repository_impl,
    local = False,
    attrs = {
        "api_level": attr.int(mandatory = True),
        "build_tools_version": attr.string(mandatory = True),
    }
)

# This is the main export for the file
def android_sdk_repository(name = None, workspace_name = None, api_level = None, build_tools_version = None):
    # Support downloading the SDK as a repository (inspired by `@yarn//yarn` )
    _android_sdk_repository(
        name = name,
        api_level = api_level,
        build_tools_version = build_tools_version,
    )

    # Create an android_sdk_repository targetting the downloaded repo
    # The path is long and convoluted because the SDK is downloaded into the runfiles of a bin target
    native.android_sdk_repository(
        name = "android_sdk_repository_" + name,
        path = "bazel-bin/external/{name}/{install_target_name}/{install_output_name}.runfiles/{workspace_name}/{sdk_root_path}".format(
                name = name,
                install_target_name = _INSTALL_TARGET_NAME,
                install_output_name = _INSTALL_OUTPUT_NAME,
                workspace_name = workspace_name,
                sdk_root_path = _SDK_ROOT_PATH),
        api_level = api_level,
        build_tools_version = build_tools_version,
    )
