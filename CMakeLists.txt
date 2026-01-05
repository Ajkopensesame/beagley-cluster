cmake_minimum_required(VERSION 3.21)

project(beagley_cluster LANGUAGES CXX)

# --------------------
# C++ configuration
# --------------------
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --------------------
# Qt
# --------------------
find_package(Qt6 REQUIRED COMPONENTS Quick WebEngineQuick Svg)

qt_standard_project_setup()

qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

# --------------------
# Executable
# --------------------
qt_add_executable(beagley_cluster
    src/main.cpp
)

qt_add_resources(beagley_cluster web_resources
    PREFIX "/web"
    FILES
        src/ui/web/map/index.html
)

# --------------------
# QML Module (THIS IS THE IMPORTANT PART)
# --------------------
qt_add_qml_module(beagley_cluster
    URI BeagleY
    VERSION 1.0

    QML_FILES
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

    RESOURCES
)

# --------------------
# Link Qt
# --------------------
target_link_libraries(beagley_cluster
    PRIVATE Qt6::Quick Qt6::WebEngineQuick Qt6::Svg
)
