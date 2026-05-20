cmake_minimum_required(VERSION 3.21)

project(beagley_cluster LANGUAGES CXX)

execute_process(
    COMMAND git -C "${CMAKE_SOURCE_DIR}" rev-parse --short=12 HEAD
    OUTPUT_VARIABLE BEAGLEY_BUILD_GIT_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
execute_process(
    COMMAND git -C "${CMAKE_SOURCE_DIR}" rev-parse --abbrev-ref HEAD
    OUTPUT_VARIABLE BEAGLEY_BUILD_GIT_BRANCH
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
execute_process(
    COMMAND git -C "${CMAKE_SOURCE_DIR}" status --porcelain
    OUTPUT_VARIABLE BEAGLEY_BUILD_GIT_STATUS
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(NOT BEAGLEY_BUILD_GIT_COMMIT)
    set(BEAGLEY_BUILD_GIT_COMMIT "unknown")
endif()
if(NOT BEAGLEY_BUILD_GIT_BRANCH)
    set(BEAGLEY_BUILD_GIT_BRANCH "unknown")
endif()
if(BEAGLEY_BUILD_GIT_STATUS)
    set(BEAGLEY_BUILD_GIT_DIRTY "dirty")
else()
    set(BEAGLEY_BUILD_GIT_DIRTY "clean")
endif()
string(TIMESTAMP BEAGLEY_BUILD_TIMESTAMP_UTC "%Y-%m-%dT%H:%M:%SZ" UTC)
message(STATUS "Beagley build identity: source=${CMAKE_SOURCE_DIR} branch=${BEAGLEY_BUILD_GIT_BRANCH} commit=${BEAGLEY_BUILD_GIT_COMMIT} dirty=${BEAGLEY_BUILD_GIT_DIRTY}")

# --------------------
# C++ configuration
# --------------------
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    message(STATUS "Defaulting CMAKE_BUILD_TYPE to RelWithDebInfo")
    set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Build type" FORCE)
endif()

# --------------------
# Feature flags
# --------------------
option(BEAGLEY_APPLIANCE_PRODUCTION "Enable the embedded appliance production profile" OFF)
option(WITH_WEBENGINE "Enable Qt WebEngine map support" ON)
option(WITH_MAPLIBRE_NATIVE "Enable the experimental MapLibre Native renderer path" OFF)

if(BEAGLEY_APPLIANCE_PRODUCTION)
    set(WITH_WEBENGINE OFF CACHE BOOL "Enable Qt WebEngine map support" FORCE)
endif()

# --------------------
# Qt
# --------------------
find_package(Qt6 REQUIRED COMPONENTS Core Network Quick Qml Svg WebSockets)

if(WITH_WEBENGINE)
    find_package(Qt6 REQUIRED COMPONENTS WebEngineQuick)
endif()

if(WITH_MAPLIBRE_NATIVE)
    find_package(Qt6 REQUIRED COMPONENTS Location Positioning)
    find_package(QMapLibre 3.0.0 EXACT COMPONENTS Location REQUIRED)
endif()

include(CheckIPOSupported)

qt_standard_project_setup()

# --------------------
# Executable
# --------------------
qt_add_executable(beagley_cluster
    src/main.cpp
    src/data/VehicleStateClient.cpp
    src/navigation/OpenNavigationProvider.cpp
    src/navigation/NavigationService.cpp
    src/render/ClusterRenderModel.cpp
    src/render/GaugeArcItem.cpp
    src/render/GaugeArcItem.h
    src/render/NativeGaugeInstrumentItem.cpp
    src/render/NativeGaugeInstrumentItem.h
    src/render/NativePanelItem.cpp
    src/render/NativePanelItem.h
    src/render/NativeRasterMapItem.cpp
    src/render/RasterFrameItem.cpp
    src/render/RasterFrameItem.h
    src/render/RadarFrameItem.cpp
    src/render/RadarFrameItem.h
    src/render/PerformanceMetrics.cpp
    src/system/NowPlayingService.cpp
    src/system/NowPlayingService.h
    src/system/RadarImageService.cpp
    src/system/RadarImageService.h
    src/system/WiFiHotspotProfiles.cpp
    src/system/WiFiSetupService.cpp
    src/system/WiFiSsidUtils.cpp
)

add_executable(nowplayingctl
    src/tools/NowPlayingCtl.cpp
)
target_link_libraries(nowplayingctl PRIVATE Qt6::Core)

target_compile_definitions(beagley_cluster PRIVATE
    "BEAGLEY_BUILD_SOURCE_PATH=\"${CMAKE_SOURCE_DIR}\""
    "BEAGLEY_BUILD_GIT_BRANCH=\"${BEAGLEY_BUILD_GIT_BRANCH}\""
    "BEAGLEY_BUILD_GIT_COMMIT=\"${BEAGLEY_BUILD_GIT_COMMIT}\""
    "BEAGLEY_BUILD_GIT_DIRTY=\"${BEAGLEY_BUILD_GIT_DIRTY}\""
    "BEAGLEY_BUILD_TIMESTAMP_UTC=\"${BEAGLEY_BUILD_TIMESTAMP_UTC}\""
)

# --------------------
# Optional Web resources (only when WebEngine is enabled)
# Goal:
#   qrc:/web/test/index.html  ->  :/web/test/index.html
#   qrc:/web/map/index.html   ->  :/web/map/index.html
#
# IMPORTANT:
# - FILES are real paths on disk (relative to repo root here).
# - BASE controls what is stripped from those paths when stored in the QRC.
# - PREFIX sets the root prefix in the compiled resource.
# --------------------
if(WITH_WEBENGINE)
    qt_add_resources(beagley_cluster web_resources
     PREFIX "/web"
        BASE "src/ui/web"
        FILES
            src/ui/web/test/index.html
            src/ui/web/map/index.html
            src/ui/web/map/styles/embedded-liberty.js
            src/ui/web/map/styles/embedded-liberty.json
            src/ui/web/map/vendor/maplibre/maplibre-gl.js
            src/ui/web/map/vendor/maplibre/maplibre-gl.css
    )
endif()

qt_add_resources(beagley_cluster app_font_resources
    PREFIX "/"
    BASE "src"
    FILES
        src/assets/fonts/Oxanium-Regular.ttf
)

# --------------------
# QML Module
# --------------------
set(BEAGLEY_QML_FILES
    src/ui/widgets/VehicleInfoCenter.qml
    src/ui/widgets/vic/VicWarningColors.qml
    src/ui/widgets/vic/VicWarningHalo.qml
    src/ui/widgets/vic/OemTellTaleIcon.qml
    src/ui/widgets/vic/telltales/AtTempTelltale.qml
    src/ui/widgets/vic/telltales/BatteryTelltale.qml
    src/ui/widgets/vic/telltales/BrakeTelltale.qml
    src/ui/widgets/vic/telltales/CheckEngineTelltale.qml
    src/ui/widgets/vic/telltales/DoorTelltale.qml
    src/ui/widgets/vic/telltales/FuelTelltale.qml
    src/ui/widgets/vic/telltales/HighBeamTelltale.qml
    src/ui/widgets/vic/telltales/MdiPathIcon.qml
    src/ui/widgets/vic/telltales/OilTelltale.qml
    src/ui/widgets/vic/telltales/WarningTelltale.qml
    src/ui/widgets/vic/icons/DriveStateIcon.qml
    src/ui/widgets/TurnChevronFlow.qml
    src/ui/widgets/GaugeChevronOrbit.qml
    src/ui/theme/PurplePearlTheme.qml
    src/ui/widgets/embedded/EmbeddedBottomRail.qml
    src/ui/widgets/embedded/EmbeddedAnalogGauge.qml
    src/ui/widgets/embedded/EmbeddedMapPod.qml
    src/ui/widgets/embedded/EmbeddedSpeedPod.qml
    src/ui/widgets/embedded/EmbeddedStatusRibbon.qml
    src/ui/widgets/embedded/EmbeddedTachPod.qml

    # Entry point
    src/ui/Main.qml
    src/ui/MainEmbedded.qml
    src/ui/MainV2.qml
    src/ui/MainV3.qml

    # Widgets
    src/ui/widgets/OemIcon.qml
    src/ui/widgets/CornerCircleShell.qml
    src/ui/widgets/CornerPodFrame.qml
    src/ui/widgets/WeatherCornerWidget.qml
    src/ui/widgets/RadarCornerWidget.qml
    src/ui/widgets/RadarGlyph.qml
    src/ui/widgets/MediaCornerWidget.qml
    src/ui/widgets/MapMenuCornerWidget.qml
    src/ui/widgets/SpeedGauge.qml
    src/ui/widgets/DialChrome.qml
    src/ui/widgets/GaugeLensShell.qml
    src/ui/widgets/GaugeArcHead.qml
    src/ui/widgets/FuelPumpIcon.qml
    src/ui/widgets/FuelGauge.qml
    src/ui/widgets/SpeedoPearl.qml
    src/ui/widgets/TachGauge.qml
    src/ui/widgets/MatrixRain.qml
    src/ui/widgets/MapCenter.qml
    src/ui/widgets/MapCenterBootShell.qml
    src/ui/widgets/MapCenterMapLibreNative.qml
    src/ui/widgets/MapLibreGaugeBackplate.qml
    src/ui/widgets/MapVehicleMarker.qml
    src/ui/widgets/WeatherCorners.qml
    src/ui/widgets/WeatherMoodIcon.qml
    src/ui/widgets/BomCatalog.js
    src/ui/widgets/HighBeamHalo.qml
    src/ui/widgets/WiFiSetupOverlay.qml
    src/ui/widgets/MapCenterNative.qml

        src/ui/widgets/MapCenterPlaceholder.qml
        src/ui/widgets/MapCenterSnapshot.qml
    # Mock data (temporary – will be replaced by BBB later)
)

# Only include the WebEngine QML file when WebEngine is enabled
if(WITH_WEBENGINE)
    list(APPEND BEAGLEY_QML_FILES
        src/ui/widgets/MapCenterWeb.qml
    )
endif()

if(WITH_MAPLIBRE_NATIVE)
    list(APPEND BEAGLEY_QML_FILES
        src/ui/widgets/MapCenterMapLibreNativeImpl.qml
    )
endif()

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/src/ui/widgets/qmldir" BEAGLEY_WIDGET_QMLDIR)
string(REGEX MATCHALL "(^|\n)[A-Za-z_][A-Za-z0-9_]*[ \t]+[0-9]+\\.[0-9]+[ \t]+[A-Za-z0-9_./-]+\\.qml" BEAGLEY_WIDGET_QMLDIR_ENTRIES "${BEAGLEY_WIDGET_QMLDIR}")
foreach(_entry IN LISTS BEAGLEY_WIDGET_QMLDIR_ENTRIES)
    string(REGEX REPLACE "^[\r\n]*[A-Za-z_][A-Za-z0-9_]*[ \t]+[0-9]+\\.[0-9]+[ \t]+" "" _qml_file "${_entry}")
    string(STRIP "${_qml_file}" _qml_file)
    set(_qml_path "src/ui/widgets/${_qml_file}")
    list(FIND BEAGLEY_QML_FILES "${_qml_path}" _qml_index)
    if(_qml_index EQUAL -1)
        message(FATAL_ERROR "QML dev/prod mismatch: ${_qml_path} is listed in src/ui/widgets/qmldir but is missing from BEAGLEY_QML_FILES")
    endif()
endforeach()

qt_add_qml_module(beagley_cluster
    URI BeagleY
    VERSION 1.0

    QML_FILES
        ${BEAGLEY_QML_FILES}
)

# --------------------
# Link Qt
# --------------------
target_link_libraries(beagley_cluster
    PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::Quick
        Qt6::Qml
        Qt6::Svg
        Qt6::WebSockets
)

if(WITH_WEBENGINE)
    target_link_libraries(beagley_cluster PRIVATE Qt6::WebEngineQuick)
    target_compile_definitions(beagley_cluster PRIVATE WITH_WEBENGINE=1)
endif()

if(WITH_MAPLIBRE_NATIVE)
    target_link_libraries(beagley_cluster PRIVATE
        Qt6::Location
        Qt6::Positioning
        QMapLibre::Location
    )
    qmaplibre_location_setup_plugins(beagley_cluster)
    target_compile_definitions(beagley_cluster PRIVATE WITH_MAPLIBRE_NATIVE=1)
endif()

if(BEAGLEY_APPLIANCE_PRODUCTION)
    target_compile_definitions(beagley_cluster PRIVATE BEAGLEY_APPLIANCE_PRODUCTION=1)
endif()

install(TARGETS beagley_cluster nowplayingctl RUNTIME DESTINATION bin)

# Qt generates the BeagleY module manifest in the build tree. Installing that
# metadata lets engine.loadFromModule("BeagleY", ...) resolve the resource-backed
# QML entries on the target image.
if(DEFINED INSTALL_QMLDIR AND NOT INSTALL_QMLDIR STREQUAL "")
    set(BEAGLEY_INSTALL_QMLDIR "${INSTALL_QMLDIR}")
else()
    set(BEAGLEY_INSTALL_QMLDIR "qml")
endif()

install(
    FILES
        "${CMAKE_CURRENT_BINARY_DIR}/BeagleY/qmldir"
        "${CMAKE_CURRENT_BINARY_DIR}/BeagleY/beagley_cluster.qmltypes"
    DESTINATION "${BEAGLEY_INSTALL_QMLDIR}/BeagleY"
)

check_ipo_supported(RESULT BEAGLEY_IPO_SUPPORTED OUTPUT BEAGLEY_IPO_ERROR)
if(BEAGLEY_IPO_SUPPORTED)
    set_property(TARGET beagley_cluster PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)
    set_property(TARGET beagley_cluster PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELWITHDEBINFO TRUE)
else()
    message(STATUS "IPO/LTO disabled: ${BEAGLEY_IPO_ERROR}")
endif()

include(CTest)
if(BUILD_TESTING)
    find_package(Python3 REQUIRED COMPONENTS Interpreter)

    add_executable(wifi_hotspot_profiles_test
        tests/wifi_hotspot_profiles_test.cpp
        src/system/WiFiHotspotProfiles.cpp
    )
    target_include_directories(wifi_hotspot_profiles_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_link_libraries(wifi_hotspot_profiles_test PRIVATE Qt6::Core)
    add_test(NAME wifi_hotspot_profiles_test COMMAND wifi_hotspot_profiles_test)

    add_executable(wifi_ssid_utils_test
        tests/wifi_ssid_utils_test.cpp
        src/system/WiFiSsidUtils.cpp
    )
    target_include_directories(wifi_ssid_utils_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_link_libraries(wifi_ssid_utils_test PRIVATE Qt6::Core)
    add_test(NAME wifi_ssid_utils_test COMMAND wifi_ssid_utils_test)

    add_executable(navigation_search_ranking_test
        tests/navigation_search_ranking_test.cpp
        src/navigation/OpenNavigationProvider.cpp
    )
    target_include_directories(navigation_search_ranking_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_link_libraries(navigation_search_ranking_test PRIVATE Qt6::Core Qt6::Network)
    add_test(NAME navigation_search_ranking_test COMMAND navigation_search_ranking_test)

    add_test(
        NAME bbb_nmea_gps_test
        COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/bbb_nmea_gps_test.py
    )
endif()
