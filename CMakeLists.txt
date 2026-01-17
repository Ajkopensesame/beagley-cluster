cmake_minimum_required(VERSION 3.21)

project(beagley_cluster LANGUAGES CXX)

# --------------------
# C++ configuration
# --------------------
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --------------------
# Feature flags
# --------------------
option(WITH_WEBENGINE "Enable Qt WebEngine map support" ON)

# --------------------
# Qt
# --------------------
find_package(Qt6 REQUIRED COMPONENTS Quick Svg)

if(WITH_WEBENGINE)
    find_package(Qt6 REQUIRED COMPONENTS WebEngineQuick)
endif()

qt_standard_project_setup()

qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

# --------------------
# Executable
# --------------------
qt_add_executable(beagley_cluster
    src/main.cpp
)

# --------------------
# Optional Web resources (only when WebEngine is enabled)
# --------------------
if(WITH_WEBENGINE)
    qt_add_resources(beagley_cluster web_resources
        PREFIX "/web"
        FILES
            src/ui/web/map/index.html
    )
endif()

# --------------------
# QML Module (THIS IS THE IMPORTANT PART)
# --------------------
set(BEAGLEY_QML_FILES
    src/ui/widgets/VehicleInfoCenter.qml
    src/ui/widgets/vic/ATIcon.qml
    src/ui/widgets/vic/VicWarningColors.qml
    src/ui/widgets/vic/VicWarningHalo.qml
    src/ui/widgets/vic/VicWarningIcon.qml
    src/ui/widgets/vic/icons/AtIcon.qml
    src/ui/widgets/vic/icons/BrakeIcon.qml
    src/ui/widgets/vic/icons/ChargeIcon.qml
    src/ui/widgets/vic/icons/CheckIcon.qml
    src/ui/widgets/vic/icons/DoorIcon.qml
    src/ui/widgets/vic/icons/FuelIcon.qml
    src/ui/widgets/vic/icons/OilIcon.qml
    src/ui/widgets/vic/warnings/AtWarning.qml
    src/ui/widgets/vic/warnings/BrakeWarning.qml
    src/ui/widgets/vic/warnings/ChargeWarning.qml
    src/ui/widgets/vic/warnings/CheckWarning.qml
    src/ui/widgets/vic/warnings/DoorWarning.qml
    src/ui/widgets/vic/warnings/FuelWarning.qml
    src/ui/widgets/TurnChevronFlow.qml
    src/ui/theme/PurplePearlTheme.qml

    # Entry point
    src/ui/Main.qml

    # Widgets
    src/ui/widgets/SpeedGauge.qml
    src/ui/widgets/FuelPumpIcon.qml
    src/ui/widgets/FuelGauge.qml
    src/ui/widgets/SpeedoPearl.qml
    src/ui/widgets/TachGauge.qml
    src/ui/widgets/MatrixRain.qml
    src/ui/widgets/MapCenter.qml

    # Mock data (temporary – will be replaced by BBB later)
    src/ui/mock/MockVehicleState.qml
)

# Only include the WebEngine QML file when WebEngine is enabled
if(WITH_WEBENGINE)
    list(APPEND BEAGLEY_QML_FILES
        src/ui/widgets/MapCenterWeb.qml
    )
endif()

qt_add_qml_module(beagley_cluster
    URI BeagleY
    VERSION 1.0

    QML_FILES
        ${BEAGLEY_QML_FILES}

    RESOURCES
)

# --------------------
# Link Qt
# --------------------
target_link_libraries(beagley_cluster
    PRIVATE
        Qt6::Quick
        Qt6::Svg
)

if(WITH_WEBENGINE)
    target_link_libraries(beagley_cluster PRIVATE Qt6::WebEngineQuick)
    target_compile_definitions(beagley_cluster PRIVATE WITH_WEBENGINE=1)
endif()
