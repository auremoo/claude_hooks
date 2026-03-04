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

INPUT=$(cat)

FILE_PATH=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    inp = d.get('tool_input', {})
    print(inp.get('file_path', '') or '')
except:
    print('')
" "$INPUT" 2>/dev/null)

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Only track firmware/embedded files
if ! echo "$FILE_PATH" | grep -qiE '\.(c|h|cpp|hpp|cc|s|asm|ld|ino|svd|dts|dtsi|cfg)$'; then
  exit 0
fi

# --- Analyze the modified file for hardware references ---
ANALYSIS=$(python3 -c "
import re, sys

file_path = sys.argv[1]
tags = set()

try:
    with open(file_path, 'r', errors='ignore') as f:
        content = f.read()
except:
    sys.exit(0)

# Detect peripherals
peripheral_patterns = {
    'GPIO': r'\b(GPIO|gpio|Pin|PIN|HAL_GPIO|GPIOA|GPIOB|GPIOC|GPIOD)\b',
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
    'IRQ': r'\b(IRQ|NVIC|interrupt|ISR|IRQHandler|__interrupt)\b',
    'CLOCK': r'\b(RCC|SystemClock|HAL_RCC|clock_|PLL|HSE|HSI)\b',
}

for name, pattern in peripheral_patterns.items():
    if re.search(pattern, content):
        tags.add(name)

# Detect register access
if re.search(r'(->|\.)(CR|SR|DR|CCR|ARR|PSC|BSRR|IDR|ODR|MODER|OTYPER|OSPEEDR|PUPDR)\b', content):
    tags.add('REGISTERS')

# Detect memory-mapped I/O
if re.search(r'#define\s+\w+_BASE\s+0x[0-9A-Fa-f]+', content):
    tags.add('MMIO')

# Detect linker script changes
if file_path.endswith('.ld') or file_path.endswith('.lds'):
    tags.add('LINKER')
    if re.search(r'(FLASH|RAM|STACK|HEAP)', content):
        if re.search(r'ORIGIN|LENGTH', content):
            tags.add('MEMORY_MAP')

if tags:
    print(','.join(sorted(tags)))
else:
    print('')
" "$FILE_PATH" 2>/dev/null)

if [ -z "$ANALYSIS" ]; then
  exit 0
fi

# --- Append to firmware changelog ---
PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CHANGELOG="$PROJECT_DIR/.claude/firmware-changelog.md"
mkdir -p "$PROJECT_DIR/.claude"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DATE=$(date '+%Y-%m-%d')
RELATIVE_PATH=$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$FILE_PATH" "$PROJECT_DIR" 2>/dev/null)

# Create header if new file
if [ ! -f "$CHANGELOG" ]; then
  echo "# Firmware Changelog" > "$CHANGELOG"
  echo "" >> "$CHANGELOG"
fi

# Add date section if needed
if ! grep -q "## $DATE" "$CHANGELOG" 2>/dev/null; then
  echo "" >> "$CHANGELOG"
  echo "## $DATE" >> "$CHANGELOG"
  echo "" >> "$CHANGELOG"
fi

echo "- \`$TIMESTAMP\` **$RELATIVE_PATH** [$ANALYSIS]" >> "$CHANGELOG"

exit 0
