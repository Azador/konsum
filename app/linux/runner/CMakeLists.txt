cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# SQLCipher aus dem System für die Matrix-Datenbank. Die Dart-Seite sucht die
# sqlite3-Funktionen im Prozess (pubspec.yaml: hooks → sqlite3 → process);
# deshalb fest verlinken, auch ohne Aufruf aus C++ (--no-as-needed).
pkg_check_modules(SQLCIPHER IMPORTED_TARGET sqlcipher)
if(NOT SQLCIPHER_FOUND)
  message(FATAL_ERROR
    "SQLCipher fehlt. Debian/Ubuntu: sudo apt install libsqlcipher-dev, "
    "Fedora: sqlcipher-devel, Arch: sqlcipher")
endif()
target_link_libraries(${BINARY_NAME} PRIVATE
  "-Wl,--push-state,--no-as-needed" PkgConfig::SQLCIPHER "-Wl,--pop-state")

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
