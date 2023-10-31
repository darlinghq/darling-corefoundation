project(corefoundation)

include(darling_framework)

remove_sdk_framework(CoreFoundation)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fblocks -fconstant-cfstrings -fexceptions \
	-include ${CMAKE_CURRENT_SOURCE_DIR}/CoreFoundation_Prefix.h \
	-include ${CMAKE_CURRENT_SOURCE_DIR}/macros.h \
	-Wno-bridge-cast \
	-mmacosx-version-min=10.10")

include_directories(
	${CMAKE_CURRENT_SOURCE_DIR}
	${CMAKE_SOURCE_DIR}/src/external/foundation/src
)

add_definitions(-DCF_BUILDING_CF
	-DDEPLOYMENT_TARGET_MACOSX=1
	-DU_SHOW_DRAFT_API=1
	-DU_SHOW_CPLUSPLUS_API=0
	-DINCLUDE_OBJC
	-DDISPATCH_SUPPORT=1
	-D__CONSTANT_CFSTRINGS__=1
	-D__CONSTANT_STRINGS__=1
	-DOBJC_OLD_DISPATCH_PROTOTYPES=1

	-w
	-nostdinc
)

set(cf_c_sources
	CFApplicationPreferences.c
	CFArray.c
	CFAttributedString.c
	CFBag.c
	CFBase.c
	CFBasicHash.c
	CFBigNumber.c
	CFBinaryHeap.c
	CFBinaryPList.c
	CFBitVector.c
	CFBuiltinConverters.c
	CFBundle_Binary.c
	CFBundle.c
	CFBundle_Grok.c
	CFBundle_InfoPlist.c
	CFBundle_Locale.c
	CFBundle_Resources.c
	CFBundle_Strings.c
	CFBurstTrie.c
	CFCalendar.c
	CFConcreteStreams.c
	CFData.c
	CFDate.c
	CFDateFormatter.c
	CFDictionary.c
	CFError.c
	CFFileUtilities.c
	CFCharacterSet.c
	CFICUConverters.c
	CFLocale.c
	CFLocaleIdentifier.c
	CFLocaleKeys.c
	CFMachPort.c
	CFMessagePort.c
	CFNotificationCenter.c
	CFNumber.c
	CFNumberFormatter.c
	CFOldStylePList.c
	CFPlatform.c
	CFPlatformConverters.c
	CFPlugIn.c
	CFPlugIn_Factory.c
	CFPlugIn_Instance.c
	CFPlugIn_PlugIn.c
	CFPreferences.c
	CFPropertyList.c
	CFRunLoop.c
	CFRuntime.c
	CFSet.c
	CFSocket.c
	CFSocketStream.c
	CFSortFunctions.c
	CFStorage.c
	CFStream.c
	CFString.c
	CFStringEncodingConverter.c
	CFStringEncodingDatabase.c
	CFStringEncodings.c
	CFStringScanner.c
	CFStringTokenizer.c
	CFStringTransform.c
	CFStringUtilities.c
	CFSystemDirectories.c
	CFTimeZone.c
	CFTree.c
	CFUnicodeDecomposition.c
	CFUnicodePrecomposition.c
	CFUniChar.c
	CFURLAccess.c
	CFURL.c
	CFURLConstants.c
	CFUserNotification.c
	CFUtilities.c
	CFUUID.c
	CFVersion.c
	CFXMLInputStream.c
	CFXMLNode.c
	CFXMLParser.c
	CFXMLPreferencesDomain.c
	CFXMLTree.c
	CFURLEnumerator.c
	CFXPCBridge.c
)

set(cf_sources
	${cf_c_sources}
	# CFStubs.m
	NSArray.m
	NSAttributedString.m
	NSBlock.m
	NSCache.m
	NSCalendar.m
	NSCFType.m
	NSConstantString.m
	NSData.m
	NSDateComponents.m
	NSDate.m
	NSDictionary.m
	NSEnumerator.m
	NSError.m
	NSException.m
	NSFastEnumerationEnumerator.m
	NSForwarding.m
	NSGenericDeallocHandler.m
	NSCharacterSet.m
	NSInputStream.m
	NSInvocation.m
	NSInvoke.S
	NSLocale.m
	NSMessageBuilder.m
	NSMethodSignature.m
	NSNull.m
	NSNumber.m
	NSObjCRuntime.m
	NSObject.m
	NSOrderedSet.m
	NSOutputStream.m
	NSPropertyList.m
	NSRunLoop.m
	NSSet.m
	NSSharedKeyDictionary.m
	NSSharedKeySet.m
	NSStream.m
	NSString.m
	NSTimer.m
	NSTimeZone.m
	NSURL.m
    NSUserDefaults.m
	NSZombie.m
	CFForwardingPrep.S
	FoundationExceptions.m
	NSRunLoopModes.m
	NSFileSecurity.m
	NSBlockInvocation.m
)

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(CoreFoundation
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/CoreFoundation"
)

add_separated_framework(CoreFoundation
	CURRENT_VERSION
	SOURCES
		${cf_sources}
	VERSION ${FRAMEWORK_VERSION}
	DEPENDENCIES
		objc
		system
		icucore
	LINK_FLAGS
		"-Wl,-init,___CFInitialize \
		-Wl,-compatibility_version,150 \
		-Wl,-current_version,1153.18 \
		-Wl,-alias_list,${CMAKE_CURRENT_SOURCE_DIR}/SymbolAliases \
		-Wl,-sectcreate,__UNICODE,__csbitmaps,${CMAKE_CURRENT_SOURCE_DIR}/CFCharacterSetBitmaps.bitmap \
		-Wl,-sectcreate,__UNICODE,__properties,${CMAKE_CURRENT_SOURCE_DIR}/CFUniCharPropertyDatabase.data \
		-Wl,-sectcreate,__UNICODE,__data,${CMAKE_CURRENT_SOURCE_DIR}/CFUnicodeData-L.mapping \
		-Wl,-segprot,__UNICODE,r,r"
)

if (TARGET_i386)
set_property(TARGET CoreFoundation_i386 APPEND_STRING PROPERTY
  LINK_FLAGS " -Wl,-reexported_symbols_list,${CMAKE_CURRENT_SOURCE_DIR}/reexport_i386.exp \
	-Wl,-alias,.objc_class_name___NSCFConstantString,___CFConstantStringClassReference")
endif (TARGET_i386)
if (TARGET_x86_64)
set_property(TARGET CoreFoundation_x86_64 APPEND_STRING PROPERTY
  LINK_FLAGS " -Wl,-reexported_symbols_list,${CMAKE_CURRENT_SOURCE_DIR}/reexport_x86_64.exp \
	-Wl,-alias,_OBJC_CLASS_\\$___NSCFConstantString,___CFConstantStringClassReference")
endif (TARGET_x86_64)
if (TARGET_ARM64)
set_property(TARGET CoreFoundation_arm64 APPEND_STRING PROPERTY
  LINK_FLAGS " -Wl,-alias,_OBJC_CLASS_\\$___NSCFConstantString,___CFConstantStringClassReference")
endif (TARGET_ARM64)

set_source_files_properties(${cf_c_sources} PROPERTIES COMPILE_FLAGS "-x objective-c")

add_darling_executable(plconvert plconvert.c)
target_link_libraries(plconvert CoreFoundation)
install(TARGETS plconvert DESTINATION libexec/darling/usr/bin)
