---
name: Self-Infinity Mono System
colors:
  surface: '#ffffff'
  on-surface: '#37352f'
  surface-container: '#ffffff'
  outline: rgba(55,53,47,.09)
  outline-variant: rgba(55,53,47,.16)
  primary: '#37352f'
  on-primary: '#ffffff'
  secondary: '#787774'
  error: '#37352f'
  surface-dim: '#ddd9d8'
  surface-bright: '#fdf8f7'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f7f3f1'
  surface-container-high: '#ebe7e6'
  surface-container-highest: '#e6e2e0'
  on-surface-variant: '#49473f'
  inverse-surface: '#31302f'
  inverse-on-surface: '#f4f0ee'
  surface-tint: '#615e57'
  primary-container: '#37352f'
  on-primary-container: '#a19d95'
  inverse-primary: '#cbc6bd'
  on-secondary: '#ffffff'
  secondary-container: '#e2dfdb'
  on-secondary-container: '#636360'
  tertiary: '#211f23'
  on-tertiary: '#ffffff'
  tertiary-container: '#363438'
  on-tertiary-container: '#a09ca1'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e7e2d9'
  primary-fixed-dim: '#cbc6bd'
  on-primary-fixed: '#1d1c16'
  on-primary-fixed-variant: '#494740'
  secondary-fixed: '#e5e2de'
  secondary-fixed-dim: '#c8c6c3'
  on-secondary-fixed: '#1b1c1a'
  on-secondary-fixed-variant: '#474744'
  tertiary-fixed: '#e6e1e6'
  tertiary-fixed-dim: '#cac5ca'
  on-tertiary-fixed: '#1c1b1f'
  on-tertiary-fixed-variant: '#48464a'
  background: '#fdf8f7'
  on-background: '#1c1b1b'
  surface-variant: '#e6e2e0'
  outline-strong: rgba(55, 53, 47, 0.16)
  hover-state: rgba(55, 53, 47, 0.08)
  dark-bg: '#191919'
  dark-text: '#e9e9e7'
  dark-dim: '#9b9b96'
  dark-outline: rgba(255, 255, 255, 0.09)
  dark-outline-strong: rgba(255, 255, 255, 0.13)
  dark-hover: rgba(255, 255, 255, 0.055)
theme:
  color_mode: LIGHT
  font: INTER
  roundness: ROUND_FOUR
  preset: MONOCHROME
  custom_color: '#37352f'
  description: Pure monochrome Notion style. Day/Night modes using only black, white,
    and greyscale. Zero saturation. 1px borders for structure.
typography:
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 18px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.02em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  unit: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  gutter: 16px
  margin-mobile: 16px
  margin-desktop: 40px
---

# Self-Infinity Monochrome Design System (Notion-Inspired)

## 1. Core Principles
- **Absolute Monochrome**: Only #000000, #FFFFFF, and neutral greys. No purple, no blue, no accent colors.
- **Notion Flatness**: 1px borders (`--border`) instead of shadows. Surfaces are solid.
- **High Contrast Day/Night**: White backgrounds for day, deep charcoal/black for night.

## 2. Color Tokens
| Token | Light (Day) | Dark (Night) | Purpose |
|---|---|---|---|
| `--bg` | `#ffffff` | `#191919` | Page background |
| `--text` | `#37352f` | `#e9e9e7` | Primary text/headings |
| `--dim` | `#787774` | `#9b9b96` | Secondary text |
| `--border` | `rgba(55,53,47,.09)` | `rgba(255,255,255,.09)` | Subtle dividers |
| `--border-strong` | `rgba(55,53,47,.16)` | `rgba(255,255,255,.13)` | Component outlines |
| `--hover` | `rgba(55,53,47,.08)` | `rgba(255,255,255,.055)` | Interaction states |
| `--accent` | `#37352f` | `#e9e9e7` | "Accent" is now just the primary text color |

## 3. UI Components
- **Panels**: White/Black background + 1px border.
- **Buttons**: Transparent by default, black/white fill for primary actions.
- **Skill Tree**: Lines are now solid black/white or dashed grey. No colored glows.
- **Progress Bars**: Simple black/white fills on grey tracks.