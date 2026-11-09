#!/usr/bin/env python3
"""Generates Dayflight.xcodeproj (Xcode 16 synchronized folders) + the shared scheme.

    python3 tools/generate_xcodeproj.py .

Synchronized folders (App, Shared, Widgets, UITests) pick up new files automatically, so this
only needs re-running when targets or build settings change. project.yml (XcodeGen) is kept
equivalent as an alternative.
"""
import hashlib, os, sys

def oid(name):
    return hashlib.md5(("dayflight:" + name).encode()).hexdigest()[:24].upper()

I = {k: oid(k) for k in [
    "project", "mainGroup", "productsGroup", "configGroup",
    "grpApp", "grpShared", "grpWidgets",
    "refApp", "refWidgets", "refPackage",
    "refXcconfig", "refAppPlist", "refWidgetPlist", "refAppEnt", "refWidgetEnt", "refProjectYml",
    "tApp", "tWidgets",
    "appSources", "appFrameworks", "appResources", "appEmbed",
    "wSources", "wFrameworks", "wResources",
    "bfAppPkg", "bfWPkg", "bfEmbed",
    "proxy", "dep",
    "pkgRef", "prodApp", "prodW",
    "cfgProjD", "cfgProjR", "cfgAppD", "cfgAppR", "cfgWD", "cfgWR",
    "listProj", "listApp", "listW",
    "grpUITests", "refUITests", "tUITests", "uiSources", "uiFrameworks", "uiResources",
    "proxyUI", "depUI", "cfgUID", "cfgUIR", "listUI",
]}

common_debug = """				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
"""

proj_debug = common_debug + """				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""
proj_release = common_debug + """				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				MTL_ENABLE_DEBUG_INFO = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
"""

app_settings = """				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = Config/Dayflight.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = "$(CURRENT_PROJECT_VERSION)";
				DEVELOPMENT_TEAM = "$(DEVELOPMENT_TEAM)";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = "Config/Dayflight-Info.plist";
				INFOPLIST_KEY_CFBundleDisplayName = Dayflight;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity";
				INFOPLIST_KEY_NSSupportsLiveActivities = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = "$(MARKETING_VERSION)";
				PRODUCT_BUNDLE_IDENTIFIER = "$(APP_BUNDLE_ID)";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) DAYFLIGHT_APP";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
"""
widget_settings = """				CODE_SIGN_ENTITLEMENTS = Config/DayflightWidgets.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = "$(CURRENT_PROJECT_VERSION)";
				DEVELOPMENT_TEAM = "$(DEVELOPMENT_TEAM)";
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = "Config/DayflightWidgets-Info.plist";
				INFOPLIST_KEY_CFBundleDisplayName = Dayflight;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = "$(MARKETING_VERSION)";
				PRODUCT_BUNDLE_IDENTIFIER = "$(APP_BUNDLE_ID).widgets";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
"""

uitest_settings = """				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = "$(CURRENT_PROJECT_VERSION)";
				DEVELOPMENT_TEAM = "$(DEVELOPMENT_TEAM)";
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = "$(MARKETING_VERSION)";
				PRODUCT_BUNDLE_IDENTIFIER = "$(APP_BUNDLE_ID).uitests";
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
				TEST_TARGET_NAME = Dayflight;
"""

def cfg(id_, name, settings, base=True):
    b = f"\t\t\tbaseConfigurationReference = {I['refXcconfig']} /* Base.xcconfig */;\n" if base else ""
    return f"""		{id_} /* {name} */ = {{
			isa = XCBuildConfiguration;
{b}			buildSettings = {{
{settings}			}};
			name = {name};
		}};
"""

out = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{I['bfAppPkg']} /* PlannerCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodApp']} /* PlannerCore */; }};
		{I['bfWPkg']} /* PlannerCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodW']} /* PlannerCore */; }};
		{I['bfEmbed']} /* DayflightWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I['refWidgets']} /* DayflightWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{I['proxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['tWidgets']};
			remoteInfo = DayflightWidgets;
		}};
		{I['proxyUI']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['tApp']};
			remoteInfo = Dayflight;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		{I['appEmbed']} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{I['bfEmbed']} /* DayflightWidgets.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		{I['refApp']} /* Dayflight.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Dayflight.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['refWidgets']} /* DayflightWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = DayflightWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['refUITests']} /* DayflightUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = DayflightUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['refPackage']} /* PlannerCore */ = {{isa = PBXFileReference; lastKnownFileType = wrapper; path = PlannerCore; sourceTree = "<group>"; }};
		{I['refXcconfig']} /* Base.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Base.xcconfig; sourceTree = "<group>"; }};
		{I['refAppPlist']} /* Dayflight-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "Dayflight-Info.plist"; sourceTree = "<group>"; }};
		{I['refWidgetPlist']} /* DayflightWidgets-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "DayflightWidgets-Info.plist"; sourceTree = "<group>"; }};
		{I['refAppEnt']} /* Dayflight.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Dayflight.entitlements; sourceTree = "<group>"; }};
		{I['refWidgetEnt']} /* DayflightWidgets.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = DayflightWidgets.entitlements; sourceTree = "<group>"; }};
		{I['refProjectYml']} /* project.yml */ = {{isa = PBXFileReference; lastKnownFileType = text.yaml; path = project.yml; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{I['grpApp']} /* App */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = App;
			sourceTree = "<group>";
		}};
		{I['grpShared']} /* Shared */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Shared;
			sourceTree = "<group>";
		}};
		{I['grpWidgets']} /* Widgets */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Widgets;
			sourceTree = "<group>";
		}};
		{I['grpUITests']} /* UITests */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = UITests;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{I['appFrameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['bfAppPkg']} /* PlannerCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['wFrameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{I['bfWPkg']} /* PlannerCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['uiFrameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I['mainGroup']} = {{
			isa = PBXGroup;
			children = (
				{I['grpApp']} /* App */,
				{I['grpShared']} /* Shared */,
				{I['grpWidgets']} /* Widgets */,
				{I['grpUITests']} /* UITests */,
				{I['refPackage']} /* PlannerCore */,
				{I['configGroup']} /* Config */,
				{I['refProjectYml']} /* project.yml */,
				{I['productsGroup']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I['configGroup']} /* Config */ = {{
			isa = PBXGroup;
			children = (
				{I['refXcconfig']} /* Base.xcconfig */,
				{I['refAppPlist']} /* Dayflight-Info.plist */,
				{I['refWidgetPlist']} /* DayflightWidgets-Info.plist */,
				{I['refAppEnt']} /* Dayflight.entitlements */,
				{I['refWidgetEnt']} /* DayflightWidgets.entitlements */,
			);
			path = Config;
			sourceTree = "<group>";
		}};
		{I['productsGroup']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I['refApp']} /* Dayflight.app */,
				{I['refWidgets']} /* DayflightWidgets.appex */,
				{I['refUITests']} /* DayflightUITests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I['tApp']} /* Dayflight */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['listApp']} /* Build configuration list for PBXNativeTarget "Dayflight" */;
			buildPhases = (
				{I['appSources']} /* Sources */,
				{I['appFrameworks']} /* Frameworks */,
				{I['appResources']} /* Resources */,
				{I['appEmbed']} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{I['dep']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{I['grpApp']} /* App */,
				{I['grpShared']} /* Shared */,
			);
			name = Dayflight;
			packageProductDependencies = (
				{I['prodApp']} /* PlannerCore */,
			);
			productName = Dayflight;
			productReference = {I['refApp']} /* Dayflight.app */;
			productType = "com.apple.product-type.application";
		}};
		{I['tWidgets']} /* DayflightWidgets */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['listW']} /* Build configuration list for PBXNativeTarget "DayflightWidgets" */;
			buildPhases = (
				{I['wSources']} /* Sources */,
				{I['wFrameworks']} /* Frameworks */,
				{I['wResources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I['grpWidgets']} /* Widgets */,
				{I['grpShared']} /* Shared */,
			);
			name = DayflightWidgets;
			packageProductDependencies = (
				{I['prodW']} /* PlannerCore */,
			);
			productName = DayflightWidgets;
			productReference = {I['refWidgets']} /* DayflightWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
		{I['tUITests']} /* DayflightUITests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['listUI']} /* Build configuration list for PBXNativeTarget "DayflightUITests" */;
			buildPhases = (
				{I['uiSources']} /* Sources */,
				{I['uiFrameworks']} /* Frameworks */,
				{I['uiResources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{I['depUI']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{I['grpUITests']} /* UITests */,
			);
			name = DayflightUITests;
			productName = DayflightUITests;
			productReference = {I['refUITests']} /* DayflightUITests.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{I['tApp']} = {{
						CreatedOnToolsVersion = 16.0;
					}};
					{I['tWidgets']} = {{
						CreatedOnToolsVersion = 16.0;
					}};
					{I['tUITests']} = {{
						CreatedOnToolsVersion = 16.0;
						TestTargetID = {I['tApp']};
					}};
				}};
			}};
			buildConfigurationList = {I['listProj']} /* Build configuration list for PBXProject "Dayflight" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {I['mainGroup']};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{I['pkgRef']} /* XCLocalSwiftPackageReference "PlannerCore" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {I['productsGroup']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I['tApp']} /* Dayflight */,
				{I['tWidgets']} /* DayflightWidgets */,
				{I['tUITests']} /* DayflightUITests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{I['appResources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['wResources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['uiResources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{I['appSources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['wSources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{I['uiSources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{I['dep']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['tWidgets']} /* DayflightWidgets */;
			targetProxy = {I['proxy']} /* PBXContainerItemProxy */;
		}};
		{I['depUI']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['tApp']} /* Dayflight */;
			targetProxy = {I['proxyUI']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{cfg(I['cfgProjD'], 'Debug', proj_debug)}{cfg(I['cfgProjR'], 'Release', proj_release)}{cfg(I['cfgAppD'], 'Debug', app_settings)}{cfg(I['cfgAppR'], 'Release', app_settings)}{cfg(I['cfgWD'], 'Debug', widget_settings)}{cfg(I['cfgWR'], 'Release', widget_settings)}{cfg(I['cfgUID'], 'Debug', uitest_settings)}{cfg(I['cfgUIR'], 'Release', uitest_settings)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{I['listProj']} /* Build configuration list for PBXProject "Dayflight" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['cfgProjD']} /* Debug */,
				{I['cfgProjR']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['listApp']} /* Build configuration list for PBXNativeTarget "Dayflight" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['cfgAppD']} /* Debug */,
				{I['cfgAppR']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['listW']} /* Build configuration list for PBXNativeTarget "DayflightWidgets" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['cfgWD']} /* Debug */,
				{I['cfgWR']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{I['listUI']} /* Build configuration list for PBXNativeTarget "DayflightUITests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I['cfgUID']} /* Debug */,
				{I['cfgUIR']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{I['pkgRef']} /* XCLocalSwiftPackageReference "PlannerCore" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = PlannerCore;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{I['prodApp']} /* PlannerCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I['pkgRef']} /* XCLocalSwiftPackageReference "PlannerCore" */;
			productName = PlannerCore;
		}};
		{I['prodW']} /* PlannerCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {I['pkgRef']} /* XCLocalSwiftPackageReference "PlannerCore" */;
			productName = PlannerCore;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {I['project']} /* Project object */;
}}
"""
root = sys.argv[1]
os.makedirs(os.path.join(root, "Dayflight.xcodeproj/project.xcworkspace"), exist_ok=True)
open(os.path.join(root, "Dayflight.xcodeproj/project.pbxproj"), "w").write(out)
open(os.path.join(root, "Dayflight.xcodeproj/project.xcworkspace/contents.xcworkspacedata"), "w").write(
"""<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
""")
def ref(target, name, product):
    return f'''<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{I[target]}"
               BuildableName = "{product}"
               BlueprintName = "{name}"
               ReferencedContainer = "container:Dayflight.xcodeproj">
            </BuildableReference>'''

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {ref('tApp', 'Dayflight', 'Dayflight.app')}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            {ref('tUITests', 'DayflightUITests', 'DayflightUITests.xctest')}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref('tApp', 'Dayflight', 'Dayflight.app')}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref('tApp', 'Dayflight', 'Dayflight.app')}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
os.makedirs(os.path.join(root, "Dayflight.xcodeproj/xcshareddata/xcschemes"), exist_ok=True)
open(os.path.join(root, "Dayflight.xcodeproj/xcshareddata/xcschemes/Dayflight.xcscheme"), "w").write(scheme)

assert len(set(I.values())) == len(I), "id collision"
print("written", len(out), "bytes")
