import SwiftUI

#if !os(tvOS)
    /// Custom round player button for macOS and older iOS versions.
    /// Filled white for prominent actions and selected toggles.
    struct PlayerControlButtonStyle: ButtonStyle {
        var diameter: CGFloat
        var isFilled = false

        func makeBody(configuration: Configuration) -> some View {
            PlayerControlButton(configuration: configuration, diameter: diameter, isFilled: isFilled)
        }

        private struct PlayerControlButton: View {
            @Environment(\.isEnabled) private var isEnabled

            let configuration: Configuration
            let diameter: CGFloat
            let isFilled: Bool

            var body: some View {
                Group {
                    if isFilled {
                        label.background(.white, in: Circle())
                    } else {
                        label.videoOverlayGlass(in: Circle())
                    }
                }
                .contentShape(Circle())
                .opacity(configuration.isPressed ? 0.7 : 1)
                #if os(macOS)
                    .hoverLift()
                #endif
            }

            private var label: some View {
                configuration.label
                    .foregroundStyle(foreground)
                    .frame(width: diameter, height: diameter)
            }

            private var foreground: Color {
                if !isEnabled {
                    return .textTertiary
                }
                return isFilled ? .black : .textPrimary
            }
        }
    }

    extension ButtonStyle where Self == PlayerControlButtonStyle {
        static func playerControl(diameter: CGFloat, isFilled: Bool = false) -> PlayerControlButtonStyle {
            PlayerControlButtonStyle(diameter: diameter, isFilled: isFilled)
        }
    }

    private struct PlayerButtonAppearance: ViewModifier {
        let diameter: CGFloat
        var isProminent = false
        var isProminentOnOlderIOS = false

        func body(content: Content) -> some View {
            #if os(iOS)
                if #available(iOS 26.0, *) {
                    Group {
                        if isProminent {
                            content
                                .foregroundStyle(.black)
                                .buttonStyle(.glassProminent)
                        } else {
                            content.buttonStyle(.glass)
                        }
                    }
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(.white)
                    .buttonSizing(.flexible)
                    .frame(width: diameter, height: diameter)
                } else {
                    content.buttonStyle(.playerControl(
                        diameter: diameter,
                        isFilled: isProminent || isProminentOnOlderIOS,
                    ))
                }
            #else
                content.buttonStyle(.playerControl(diameter: diameter, isFilled: isProminent))
            #endif
        }
    }

    struct PlayerIconButton: View {
        enum Size {
            /// Header and corner buttons, such as settings or rotation lock.
            case small
            /// Seek buttons beside play.
            case regular

            var diameter: CGFloat {
                switch self {
                case .small:
                    #if os(macOS)
                        36
                    #else
                        44
                    #endif
                case .regular:
                    #if os(macOS)
                        44
                    #else
                        58
                    #endif
                }
            }

            var font: Font {
                switch self {
                case .small:
                    .headline.weight(.semibold)
                case .regular:
                    .title3.weight(.bold)
                }
            }
        }

        let systemName: String
        var accessibilityLabel: String?
        var size: Size = .regular
        var isSelected = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(size.font)
            }
            .modifier(PlayerButtonAppearance(diameter: size.diameter, isProminent: isSelected))
            .accessibilityLabel(accessibilityLabel ?? systemName)
        }
    }

    struct PlayPauseButton: View {
        var isPaused: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(font)
            }
            #if os(iOS)
            .modifier(PlayerButtonAppearance(diameter: diameter, isProminentOnOlderIOS: true))
            #else
            .modifier(PlayerButtonAppearance(diameter: diameter, isProminent: true))
            #endif
            .accessibilityLabel(isPaused
                ? String(localized: "common.actions.play")
                : String(localized: "common.actions.pause"))
        }

        private var diameter: CGFloat {
            #if os(macOS)
                56
            #else
                72
            #endif
        }

        private var font: Font {
            #if os(macOS)
                .title2.weight(.black)
            #else
                .title.weight(.black)
            #endif
        }
    }
#endif
