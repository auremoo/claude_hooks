#!/bin/bash
# =============================================================================
# Claude Code PostToolUse Hook - Firmware Changelog
# =============================================================================
# Maintains a firmware-specific changelog tracking:
# - Modified files with hardware register references
# - Peripheral/driver changes
# - Pin/GPIO modifications
# - Timer/interrupt changes
# Stored in .claude/firmware-changelog.md
# =============================================================================

HOOK_DIR=${BASH_SOURCE[0]%/*}; [ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR=.
if [ -f "$HOOK_DIR/_common.sh" ]; then . "$HOOK_DIR/_common.sh"; else . "$HOOK_DIR/../_common.sh" || exit 1; fi

main() {
  local FILE_PATH PROJECT_DIR PYCODE REPLY

  get_file_path || return 0
  [ -f "$FILE_PATH" ] || return 0

  # Only track firmware/embedded files
  has_ext 'c|h|cpp|hpp|cc|s|asm|ld|lds|ino|svd|dts|dtsi|cfg' nocase || return 0

  # --- Analyze the modified file for hardware references ---
  IFS= read -r -d '' PYCODE <<'PYEOF'
content = read_file(PATH)
if content is None:
    sys.exit(0)
tags = set()

# Peripherals
PERIPHERALS = {
    'GPIO': r'\b(GPIO|gpio|Pin|PIN|HAL_GPIO|GPIO[A-K])\b',
    'UART': r'\b(UART|USART|Serial|HAL_UART|LPUART)\b',
    'SPI': r'\b(SPI|HAL_SPI|spi_)\b',
    'I2C': r'\b(I2C|HAL_I2C|i2c_|TWI)\b',
    'TIMER': r'\b(TIM|Timer|HAL_TIM|timer_|PWM|pwm)\b',
    'ADC': r'\b(ADC|HAL_ADC|adc_|AnalogIn)\b',
    'DAC': r'\b(DAC|HAL_DAC|dac_|AnalogOut)\b',
    'DMA': r'\b(DMA|HAL_DMA|dma_)\b',
    'CAN': r'\b(CAN|HAL_CAN|can_|FDCAN)\b',
    'ETH': r'\b(ETH|HAL_ETH|eth_|Ethernet)\b',
    'USB': r'\b(USB|HAL_USB|usb_|USBD)\b',
    'RTC': r'\b(RTC|HAL_RTC|rtc_)\b',
    'WATCHDOG': r'\b(WDG|IWDG|WWDG|watchdog|HAL_IWDG)\b',
    'FLASH': r'\b(FLASH|HAL_FLASH|flash_|NVM)\b',
    'IRQ': r'\b(IRQ|NVIC|interrupt|ISR|\w*IRQHandler|__interrupt)\b',
    'CLOCK': r'\b(RCC|SystemClock|HAL_RCC|clock_|PLL|HSE|HSI)\b',
}
for name, pattern in PERIPHERALS.items():
    if re.search(pattern, content):
        tags.add(name)

# Register access
if re.search(r'(->|\.)(CR|SR|DR|CCR|ARR|PSC|BSRR|IDR|ODR|MODER|OTYPER|OSPEEDR|PUPDR)\b', content):
    tags.add('REGISTERS')

# Memory-mapped I/O
if re.search(r'#define\s+\w+_BASE\s+0x[0-9A-Fa-f]+', content):
    tags.add('MMIO')

# Linker script changes
if PATH.lower().endswith(('.ld', '.lds')):
    tags.add('LINKER')
    if re.search(r'(FLASH|RAM|STACK|HEAP)', content) and re.search(r'ORIGIN|LENGTH', content):
        tags.add('MEMORY_MAP')

if not tags:
    sys.exit(0)

# --- Append to the firmware changelog ---
import os, time

project_dir = ARGS[0]
relative = PATH
try:
    candidate = os.path.relpath(PATH, project_dir).replace('\\', '/')
    if not candidate.startswith('..'):
        relative = candidate
except ValueError:
    pass  # file on another drive (Windows)

changelog = os.path.join(project_dir, '.claude', 'firmware-changelog.md')
os.makedirs(os.path.dirname(changelog), exist_ok=True)
existing = read_file(changelog) or ''
date = time.strftime('%Y-%m-%d')
with open(changelog, 'a', encoding='utf-8', newline='\n') as f:
    if not existing:
        f.write('# Firmware Changelog\n\n')
    if '## ' + date not in existing:
        f.write('\n## %s\n\n' % date)
    f.write('- `%s` **%s** [%s]\n' % (time.strftime('%Y-%m-%d %H:%M:%S'), relative, ','.join(sorted(tags))))
PYEOF

  get_project_dir
  run_py "$PYCODE" "$PROJECT_DIR"
  return 0
}

main
