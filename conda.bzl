load(":utils.bzl", "INSTALLER_SCRIPT_EXT_MAP", "CONDA_EXT_MAP", "get_os", "get_arch", "execute_waitable_windows", "windowsify")

# CONDA CONFIGURATION
CONDA_MAJOR = "3"
CONDA_MINOR = "py38_4.8.3"
CONDA_SHA = {
    "Windows": {
        "x86_64" : "1f4ff67f051c815b6008f144fdc4c3092af2805301d248b56281c36c1f4333e5",
        "x86" : "415920293ae005a17afaef4c275bd910b06c07d8adf5e0cbc9c69f0f890df976"
    },
    "MacOSX": {
        "x86_64" : "9b9a353fadab6aa82ac0337c367c23ef842f97868dcbb2ff25ec3aa463afc871"
    },
    "Linux": {
        "x86_64" : "879457af6a0bf5b34b48c12de31d4df0ee2f06a8e68768e5758c3293b2daf688",
        "ppc64le" : "362705630a9e85faf29c471faa8b0a48eabfe2bf87c52e4c180825f9215d313c"
    }
}
CONDA_INSTALLER_NAME_TEMPLATE = "Miniconda{major}-{minor}-{os}-{arch}{ext}"
CONDA_BASE_URL = "https://repo.anaconda.com/miniconda/"
CONDA_INSTALLER_FLAGS = {
    "Windows": ["/InstallationType=JustMe", "/AddToPath=0", "/RegisterPython=0", "/S", "/D={}"],
    "MacOSX": ["-b", "-f", "-p", "{}"],
    "Linux": ["-b", "-f", "-p", "{}"]
}

INSTALLER_DIR = "installer"

CONDA_BUILD_FILE_TEMPLATE = """# This file was automatically generated by rules_conda

exports_files(['{conda}'])
"""

def _get_installer_flags(rctx, dir):
    os = get_os(rctx)
    flags = CONDA_INSTALLER_FLAGS[os]
    # insert directory
    dir = rctx.path(dir)
    if os == "Windows":
        dir = windowsify(dir)
    return flags[:-1] + [flags[-1].format(dir)]


# download conda installer
def _download_conda(rctx):
    rctx.report_progress("Downloading conda installer")
    os = get_os(rctx)
    arch = get_arch(rctx)
    ext = INSTALLER_SCRIPT_EXT_MAP[os]
    url = CONDA_BASE_URL + CONDA_INSTALLER_NAME_TEMPLATE.format(major=CONDA_MAJOR, minor=CONDA_MINOR, os=os, arch=arch, ext=ext)
    output = "{}/install{}".format(INSTALLER_DIR, ext)
    # download from url to output
    rctx.download(
        url = url,
        output = output,
        sha256 = CONDA_SHA[os][arch],
        executable = True
    )
    return output


# install conda locally
def _install_conda(rctx, installer):
    rctx.report_progress("Installing conda")
    os = get_os(rctx)
    installer_flags = _get_installer_flags(rctx, rctx.attr.conda_dir)
    args = [rctx.path(installer)] + installer_flags

    # execute installer with flags adjusted to OS
    if os == "Windows":
        # TODO: fix always returning 0
        # it seems that either miniconda installer returns 0 even on failure or the wrapper does something wrong
        # also stdout and stderr are always empty
        result = execute_waitable_windows(rctx, args, quiet=rctx.attr.quiet, environment={"CONDA_DLL_SEARCH_MODIFICATION_ENABLE": ""})
    else:
        result = rctx.execute(args, quiet=rctx.attr.quiet)

    if result.return_code:
        fail("Failure installing conda.\n{}\n{}".format(result.stdout, result.stderr))
    return "{}/condabin/conda{}".format(rctx.attr.conda_dir, CONDA_EXT_MAP[os])


# use conda to update itself
def _update_conda(rctx, executable):
    conda_with_version = "conda={}".format(rctx.attr.version)
    args = [rctx.path(executable), "install", conda_with_version, "-y"]
    # update conda itself
    result = rctx.execute(args, quiet=rctx.attr.quiet, working_directory=rctx.attr.conda_dir)
    if result.return_code:
        fail("Failure updating conda.\n{}\n{}".format(result.stdout, result.stderr))


# create BUILD file with exposed conda binary
def _create_conda_build_file(rctx, executable):
    conda = "{}/{}".format(rctx.attr.conda_dir, executable)
    rctx.file(
        "BUILD",
        content = CONDA_BUILD_FILE_TEMPLATE.format(conda=conda)
    )


def _load_conda_impl(rctx):
    installer = _download_conda(rctx)
    executable = _install_conda(rctx, installer)
    _update_conda(rctx, executable)
    _create_conda_build_file(rctx, executable)


load_conda_rule = repository_rule(
    _load_conda_impl,
    attrs = {
        "conda_dir": attr.string(mandatory=True),
        "version": attr.string(
            mandatory = True,
            doc = "Conda version to install"
        ),
        "quiet": attr.bool(
            default = True,
            doc = "False if conda output should be shown"
        )
    }
)
