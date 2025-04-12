# Specify the name of the executable.
add_executable(assign02)

# Initialize the Pico SDK.
pico_sdk_init()

pico_generate_pio_header(assign02 ${CMAKE_CURRENT_LIST_DIR}/ws2812.pio)

# Specify the source files to be compiled.
target_sources(assign02 PRIVATE assign02.c assign02.S)

# Enable UART for stdio
pico_enable_stdio_usb(assign02 0)
pico_enable_stdio_uart(assign02 1)

# Pull in commonly used features.
target_link_libraries(assign02
    pico_stdlib
    hardware_timer
    hardware_pio
    hardware_irq  
)

# Create map/bin/hex file etc.
pico_add_extra_outputs(assign02)

# Add the URL via pico_set_program_url.
apps_auto_set_url(assign02)