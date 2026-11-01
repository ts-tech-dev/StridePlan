#!/usr/bin/env python3
"""
Writes StridePlan.xcodeproj/project.pbxproj (Xcode 16+, object version 77).

Source folders are "synchronized groups": any file added under StridePlan/, Shared/, LiveActivity/ or Tests/
is picked up by Xcode automatically, so you rarely need to rerun this. It exists so the project can be
regenerated deterministically (e.g. after renaming targets).

Targets
  StridePlan               iOS app            ← StridePlan/ + Shared/
  StridePlanLiveActivity   Widget extension   ← LiveActivity/ + Shared/
  StridePlanTests          Unit tests         ← Tests/ (hosted by the app)

Swift packages
  ConnectIQ (garmin/connectiq-companion-app-sdk-ios)  linked into the app for the Garmin watch connection
"""
import hashlib
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
PROJ = os.path.join(ROOT, "StridePlan.xcodeproj")


def oid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


APP, EXT, TESTS = "StridePlan", "StridePlanLiveActivity", "StridePlanTests"
ids = {k: oid(k) for k in [
    "project", "mainGroup", "productsGroup", "configGroup",
    "grp.StridePlan", "grp.Shared", "grp.LiveActivity", "grp.Tests",
    "ref.app", "ref.ext", "ref.tests",
    "ref.appPlist", "ref.extPlist", "ref.entitlements", "ref.xcconfig",
    "t.app", "t.ext", "t.tests",
    "app.sources", "app.frameworks", "app.resources", "app.embed",
    "ext.sources", "ext.frameworks", "ext.resources",
    "tests.sources", "tests.frameworks", "tests.resources",
    "bf.embedExt", "bf.connectIQ", "pkg.connectIQ", "prod.connectIQ",
    "proxy.ext", "proxy.app", "dep.ext", "dep.app",
    "cfgList.project", "cfgList.app", "cfgList.ext", "cfgList.tests",
    "cfg.project.Debug", "cfg.project.Release",
    "cfg.app.Debug", "cfg.app.Release",
    "cfg.ext.Debug", "cfg.ext.Release",
    "cfg.tests.Debug", "cfg.tests.Release",
]}


def settings(d, indent=4):
    pad = "\t" * indent
    lines = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            items = "".join(f'{pad}\t"{x}",\n' for x in v)
            lines.append(f"{pad}{k} = (\n{items}{pad});")
        else:
            s = str(v)
            if s == "" or any(c in s for c in ' $()-+/.,=<>@"') and not s.replace(".", "").isdigit():
                s = '"' + s.replace('"', '\\"') + '"'
            lines.append(f"{pad}{k} = {s};")
    return "\n".join(lines)


PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_COMMA": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
}
PROJECT_DEBUG = {**PROJECT_COMMON,
                 "DEBUG_INFORMATION_FORMAT": "dwarf",
                 "ENABLE_TESTABILITY": "YES",
                 "GCC_DYNAMIC_NO_PIC": "NO",
                 "GCC_OPTIMIZATION_LEVEL": "0",
                 "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
                 "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
                 "ONLY_ACTIVE_ARCH": "YES",
                 "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
                 "SWIFT_OPTIMIZATION_LEVEL": "-Onone"}
PROJECT_RELEASE = {**PROJECT_COMMON,
                   "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                   "ENABLE_NS_ASSERTIONS": "NO",
                   "MTL_ENABLE_DEBUG_INFO": "NO",
                   "SWIFT_COMPILATION_MODE": "wholemodule",
                   "VALIDATE_PRODUCT": "YES"}

# DEVELOPMENT_TEAM is inherited from Config/Shared.xcconfig (project-level base configuration).
SIGNING = {"CODE_SIGN_STYLE": "Automatic"}

APP_SETTINGS = {**SIGNING,
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                "CODE_SIGN_ENTITLEMENTS": "Config/StridePlan.entitlements",
                "CURRENT_PROJECT_VERSION": "1",
                "ENABLE_PREVIEWS": "YES",
                "GENERATE_INFOPLIST_FILE": "YES",
                "INFOPLIST_FILE": "Config/StridePlan-Info.plist",
                "INFOPLIST_KEY_CFBundleDisplayName": "$(APP_DISPLAY_NAME)",
                "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.healthcare-fitness",
                "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
                "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
                "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
                "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
                "MARKETING_VERSION": "1.0",
                "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_PREFIX)",
                "PRODUCT_NAME": "$(TARGET_NAME)",
                "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
                "SUPPORTS_MACCATALYST": "NO",
                "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
                "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
                "SWIFT_EMIT_LOC_STRINGS": "YES",
                "TARGETED_DEVICE_FAMILY": "1"}

EXT_SETTINGS = {**SIGNING,
                "CURRENT_PROJECT_VERSION": "1",
                "GENERATE_INFOPLIST_FILE": "YES",
                "INFOPLIST_FILE": "Config/LiveActivity-Info.plist",
                "INFOPLIST_KEY_CFBundleDisplayName": "$(APP_DISPLAY_NAME)",
                "INFOPLIST_KEY_NSHumanReadableCopyright": "",
                "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
                "MARKETING_VERSION": "1.0",
                "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_PREFIX).LiveActivity",
                "PRODUCT_NAME": "$(TARGET_NAME)",
                "SKIP_INSTALL": "YES",
                "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
                "SWIFT_EMIT_LOC_STRINGS": "YES",
                "TARGETED_DEVICE_FAMILY": "1"}

TEST_SETTINGS = {**SIGNING,
                 "BUNDLE_LOADER": "$(TEST_HOST)",
                 "CURRENT_PROJECT_VERSION": "1",
                 "GENERATE_INFOPLIST_FILE": "YES",
                 "MARKETING_VERSION": "1.0",
                 "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_PREFIX).tests",
                 "PRODUCT_NAME": "$(TARGET_NAME)",
                 "SWIFT_EMIT_LOC_STRINGS": "NO",
                 "TARGETED_DEVICE_FAMILY": "1",
                 "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/StridePlan.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/StridePlan"}


def config(key, name, values, base=None):
    base_line = f"\t\t\tbaseConfigurationReference = {ids['ref.xcconfig']} /* Shared.xcconfig */;\n" if base else ""
    return (f"\t\t{ids[key]} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n{base_line}"
            f"\t\t\tbuildSettings = {{\n{settings(values)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")


def phase(key, isa, name, files=""):
    return (f"\t\t{ids[key]} /* {name} */ = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n"
            f"\t\t\tfiles = (\n{files}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")


CONNECTIQ_URL = "https://github.com/garmin/connectiq-companion-app-sdk-ios"
CONNECTIQ_MIN_VERSION = "1.8.0"


def target(key, name, product_ref, product_name, product_type, cfg_list, phases, groups, deps=(), packages=()):
    phase_lines = "".join(f"\t\t\t\t{ids[p]} /* {n} */,\n" for p, n in phases)
    package_lines = "".join(f"\t\t\t\t{ids[k]} /* {n} */,\n" for k, n in packages)
    group_lines = "".join(f"\t\t\t\t{ids[g]} /* {n} */,\n" for g, n in groups)
    dep_lines = "".join(f"\t\t\t\t{ids[d]} /* PBXTargetDependency */,\n" for d in deps)
    return (f"\t\t{ids[key]} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
            f"\t\t\tbuildConfigurationList = {ids[cfg_list]} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n"
            f"\t\t\tbuildPhases = (\n{phase_lines}\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n"
            f"\t\t\tdependencies = (\n{dep_lines}\t\t\t);\n"
            f"\t\t\tfileSystemSynchronizedGroups = (\n{group_lines}\t\t\t);\n"
            f"\t\t\tname = {name};\n\t\t\tpackageProductDependencies = (\n{package_lines}\t\t\t);\n"
            f"\t\t\tproductName = {name};\n\t\t\tproductReference = {ids[product_ref]} /* {product_name} */;\n"
            f"\t\t\tproductType = \"{product_type}\";\n\t\t}};\n")


def cfg_list(key, comment, debug, release):
    return (f"\t\t{ids[key]} /* Build configuration list for {comment} */ = {{\n\t\t\tisa = XCConfigurationList;\n"
            f"\t\t\tbuildConfigurations = (\n\t\t\t\t{ids[debug]} /* Debug */,\n\t\t\t\t{ids[release]} /* Release */,\n\t\t\t);\n"
            f"\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")


def build():
    o = []
    o.append("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n\n")

    o.append("/* Begin PBXBuildFile section */\n")
    o.append(f"\t\t{ids['bf.embedExt']} /* {EXT}.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; "
             f"fileRef = {ids['ref.ext']} /* {EXT}.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")
    o.append(f"\t\t{ids['bf.connectIQ']} /* ConnectIQ in Frameworks */ = {{isa = PBXBuildFile; "
             f"productRef = {ids['prod.connectIQ']} /* ConnectIQ */; }};\n")
    o.append("/* End PBXBuildFile section */\n\n")

    o.append("/* Begin PBXContainerItemProxy section */\n")
    for key, tkey, name in (("proxy.ext", "t.ext", EXT), ("proxy.app", "t.app", APP)):
        o.append(f"\t\t{ids[key]} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n"
                 f"\t\t\tcontainerPortal = {ids['project']} /* Project object */;\n\t\t\tproxyType = 1;\n"
                 f"\t\t\tremoteGlobalIDString = {ids[tkey]};\n\t\t\tremoteInfo = {name};\n\t\t}};\n")
    o.append("/* End PBXContainerItemProxy section */\n\n")

    o.append("/* Begin PBXCopyFilesBuildPhase section */\n")
    o.append(f"\t\t{ids['app.embed']} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n"
             f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n"
             f"\t\t\tfiles = (\n\t\t\t\t{ids['bf.embedExt']} /* {EXT}.appex in Embed Foundation Extensions */,\n\t\t\t);\n"
             f"\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    o.append("/* End PBXCopyFilesBuildPhase section */\n\n")

    o.append("/* Begin PBXFileReference section */\n")
    o.append(f"\t\t{ids['ref.app']} /* {APP}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
             f"includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    o.append(f"\t\t{ids['ref.ext']} /* {EXT}.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; "
             f"includeInIndex = 0; path = {EXT}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    o.append(f"\t\t{ids['ref.tests']} /* {TESTS}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; "
             f"includeInIndex = 0; path = {TESTS}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    for key, path, ftype in (("ref.appPlist", "StridePlan-Info.plist", "text.plist.xml"),
                             ("ref.extPlist", "LiveActivity-Info.plist", "text.plist.xml"),
                             ("ref.entitlements", "StridePlan.entitlements", "text.plist.entitlements"),
                             ("ref.xcconfig", "Shared.xcconfig", "text.xcconfig")):
        o.append(f"\t\t{ids[key]} /* {path} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; "
                 f"path = {path}; sourceTree = \"<group>\"; }};\n")
    o.append("/* End PBXFileReference section */\n\n")

    o.append("/* Begin PBXFileSystemSynchronizedRootGroup section */\n")
    for key, path in (("grp.StridePlan", "StridePlan"), ("grp.Shared", "Shared"),
                      ("grp.LiveActivity", "LiveActivity"), ("grp.Tests", "Tests")):
        o.append(f"\t\t{ids[key]} /* {path} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
                 f"\t\t\tpath = {path};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    o.append("/* End PBXFileSystemSynchronizedRootGroup section */\n\n")

    o.append("/* Begin PBXFrameworksBuildPhase section */\n")
    o.append(phase("app.frameworks", "PBXFrameworksBuildPhase", "Frameworks",
                   f"\t\t\t\t{ids['bf.connectIQ']} /* ConnectIQ in Frameworks */,\n"))
    for k in ("ext.frameworks", "tests.frameworks"):
        o.append(phase(k, "PBXFrameworksBuildPhase", "Frameworks"))
    o.append("/* End PBXFrameworksBuildPhase section */\n\n")

    o.append("/* Begin PBXGroup section */\n")
    o.append(f"\t\t{ids['mainGroup']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
             f"\t\t\t\t{ids['grp.StridePlan']} /* StridePlan */,\n\t\t\t\t{ids['grp.Shared']} /* Shared */,\n"
             f"\t\t\t\t{ids['grp.LiveActivity']} /* LiveActivity */,\n\t\t\t\t{ids['grp.Tests']} /* Tests */,\n"
             f"\t\t\t\t{ids['configGroup']} /* Config */,\n\t\t\t\t{ids['productsGroup']} /* Products */,\n"
             f"\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    o.append(f"\t\t{ids['configGroup']} /* Config */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
             f"\t\t\t\t{ids['ref.xcconfig']} /* Shared.xcconfig */,\n\t\t\t\t{ids['ref.appPlist']} /* StridePlan-Info.plist */,\n"
             f"\t\t\t\t{ids['ref.extPlist']} /* LiveActivity-Info.plist */,\n\t\t\t\t{ids['ref.entitlements']} /* StridePlan.entitlements */,\n"
             f"\t\t\t);\n\t\t\tpath = Config;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    o.append(f"\t\t{ids['productsGroup']} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
             f"\t\t\t\t{ids['ref.app']} /* {APP}.app */,\n\t\t\t\t{ids['ref.ext']} /* {EXT}.appex */,\n"
             f"\t\t\t\t{ids['ref.tests']} /* {TESTS}.xctest */,\n"
             f"\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    o.append("/* End PBXGroup section */\n\n")

    o.append("/* Begin PBXNativeTarget section */\n")
    o.append(target("t.app", APP, "ref.app", f"{APP}.app", "com.apple.product-type.application", "cfgList.app",
                    [("app.sources", "Sources"), ("app.frameworks", "Frameworks"), ("app.resources", "Resources"),
                     ("app.embed", "Embed Foundation Extensions")],
                    [("grp.StridePlan", "StridePlan"), ("grp.Shared", "Shared")], deps=["dep.ext"],
                    packages=[("prod.connectIQ", "ConnectIQ")]))
    o.append(target("t.ext", EXT, "ref.ext", f"{EXT}.appex", "com.apple.product-type.app-extension", "cfgList.ext",
                    [("ext.sources", "Sources"), ("ext.frameworks", "Frameworks"), ("ext.resources", "Resources")],
                    [("grp.LiveActivity", "LiveActivity"), ("grp.Shared", "Shared")]))
    o.append(target("t.tests", TESTS, "ref.tests", f"{TESTS}.xctest", "com.apple.product-type.bundle.unit-test", "cfgList.tests",
                    [("tests.sources", "Sources"), ("tests.frameworks", "Frameworks"), ("tests.resources", "Resources")],
                    [("grp.Tests", "Tests")], deps=["dep.app"]))
    o.append("/* End PBXNativeTarget section */\n\n")

    o.append("/* Begin PBXProject section */\n")
    o.append(f"\t\t{ids['project']} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n"
             f"\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1600;\n\t\t\t\tLastUpgradeCheck = 1600;\n"
             f"\t\t\t\tTargetAttributes = {{\n"
             f"\t\t\t\t\t{ids['t.app']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n"
             f"\t\t\t\t\t{ids['t.ext']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n"
             f"\t\t\t\t\t{ids['t.tests']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t\tTestTargetID = {ids['t.app']};\n\t\t\t\t\t}};\n"
             f"\t\t\t\t}};\n\t\t\t}};\n"
             f"\t\t\tbuildConfigurationList = {ids['cfgList.project']} /* Build configuration list for PBXProject \"StridePlan\" */;\n"
             f"\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
             f"\t\t\tmainGroup = {ids['mainGroup']};\n\t\t\tminimizedProjectReferenceProxies = 1;\n"
             f"\t\t\tpackageReferences = (\n"
             f"\t\t\t\t{ids['pkg.connectIQ']} /* XCRemoteSwiftPackageReference \"connectiq-companion-app-sdk-ios\" */,\n\t\t\t);\n"
             f"\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {ids['productsGroup']} /* Products */;\n"
             f"\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n"
             f"\t\t\t\t{ids['t.app']} /* {APP} */,\n\t\t\t\t{ids['t.ext']} /* {EXT} */,\n\t\t\t\t{ids['t.tests']} /* {TESTS} */,\n"
             f"\t\t\t);\n\t\t}};\n")
    o.append("/* End PBXProject section */\n\n")

    o.append("/* Begin PBXResourcesBuildPhase section */\n")
    for k in ("app.resources", "ext.resources", "tests.resources"):
        o.append(phase(k, "PBXResourcesBuildPhase", "Resources"))
    o.append("/* End PBXResourcesBuildPhase section */\n\n")

    o.append("/* Begin PBXSourcesBuildPhase section */\n")
    for k in ("app.sources", "ext.sources", "tests.sources"):
        o.append(phase(k, "PBXSourcesBuildPhase", "Sources"))
    o.append("/* End PBXSourcesBuildPhase section */\n\n")

    o.append("/* Begin PBXTargetDependency section */\n")
    for key, tkey, proxy, name in (("dep.ext", "t.ext", "proxy.ext", EXT), ("dep.app", "t.app", "proxy.app", APP)):
        o.append(f"\t\t{ids[key]} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n"
                 f"\t\t\ttarget = {ids[tkey]} /* {name} */;\n\t\t\ttargetProxy = {ids[proxy]} /* PBXContainerItemProxy */;\n\t\t}};\n")
    o.append("/* End PBXTargetDependency section */\n\n")

    o.append("/* Begin XCBuildConfiguration section */\n")
    o.append(config("cfg.project.Debug", "Debug", PROJECT_DEBUG, base=True))
    o.append(config("cfg.project.Release", "Release", PROJECT_RELEASE, base=True))
    o.append(config("cfg.app.Debug", "Debug", APP_SETTINGS))
    o.append(config("cfg.app.Release", "Release", APP_SETTINGS))
    o.append(config("cfg.ext.Debug", "Debug", EXT_SETTINGS))
    o.append(config("cfg.ext.Release", "Release", EXT_SETTINGS))
    o.append(config("cfg.tests.Debug", "Debug", TEST_SETTINGS))
    o.append(config("cfg.tests.Release", "Release", TEST_SETTINGS))
    o.append("/* End XCBuildConfiguration section */\n\n")

    o.append("/* Begin XCConfigurationList section */\n")
    o.append(cfg_list("cfgList.project", 'PBXProject "StridePlan"', "cfg.project.Debug", "cfg.project.Release"))
    o.append(cfg_list("cfgList.app", f'PBXNativeTarget "{APP}"', "cfg.app.Debug", "cfg.app.Release"))
    o.append(cfg_list("cfgList.ext", f'PBXNativeTarget "{EXT}"', "cfg.ext.Debug", "cfg.ext.Release"))
    o.append(cfg_list("cfgList.tests", f'PBXNativeTarget "{TESTS}"', "cfg.tests.Debug", "cfg.tests.Release"))
    o.append("/* End XCConfigurationList section */\n\n")

    o.append("/* Begin XCRemoteSwiftPackageReference section */\n")
    o.append(f"\t\t{ids['pkg.connectIQ']} /* XCRemoteSwiftPackageReference \"connectiq-companion-app-sdk-ios\" */ = {{\n"
             f"\t\t\tisa = XCRemoteSwiftPackageReference;\n\t\t\trepositoryURL = \"{CONNECTIQ_URL}\";\n"
             f"\t\t\trequirement = {{\n\t\t\t\tkind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = {CONNECTIQ_MIN_VERSION};\n\t\t\t}};\n\t\t}};\n")
    o.append("/* End XCRemoteSwiftPackageReference section */\n\n")

    o.append("/* Begin XCSwiftPackageProductDependency section */\n")
    o.append(f"\t\t{ids['prod.connectIQ']} /* ConnectIQ */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n"
             f"\t\t\tpackage = {ids['pkg.connectIQ']} /* XCRemoteSwiftPackageReference \"connectiq-companion-app-sdk-ios\" */;\n"
             f"\t\t\tproductName = ConnectIQ;\n\t\t}};\n")
    o.append("/* End XCSwiftPackageProductDependency section */\n")

    o.append(f"\t}};\n\trootObject = {ids['project']} /* Project object */;\n}}\n")
    return "".join(o)


SCHEME = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['t.app']}" BuildableName = "{APP}.app" BlueprintName = "{APP}" ReferencedContainer = "container:StridePlan.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES" shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['t.tests']}" BuildableName = "{TESTS}.xctest" BlueprintName = "{TESTS}" ReferencedContainer = "container:StridePlan.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['t.app']}" BuildableName = "{APP}.app" BlueprintName = "{APP}" ReferencedContainer = "container:StridePlan.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['t.app']}" BuildableName = "{APP}.app" BlueprintName = "{APP}" ReferencedContainer = "container:StridePlan.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

if __name__ == "__main__":
    os.makedirs(os.path.join(PROJ, "xcshareddata", "xcschemes"), exist_ok=True)
    with open(os.path.join(PROJ, "project.pbxproj"), "w") as f:
        f.write(build())
    with open(os.path.join(PROJ, "xcshareddata", "xcschemes", "StridePlan.xcscheme"), "w") as f:
        f.write(SCHEME)
    print("wrote", os.path.normpath(PROJ))
