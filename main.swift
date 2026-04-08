import AppKit
import SwiftUI

// Notification used to open files from Finder
extension Notification.Name {
    static let openFileFromFinder = Notification.Name("openFileFromFinder")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacDevUtils"
        window.contentView = NSHostingView(rootView: ContentView())
        window.minSize = NSSize(width: 900, height: 580)
        window.center()
        window.setFrameAutosaveName("MacDevUtils")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        NotificationCenter.default.post(name: .openFileFromFinder, object: url)
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            NotificationCenter.default.post(name: .openFileFromFinder, object: url)
        }
    }
}

// MARK: - Entry Point
// Global reference so ARC doesn't release the delegate (NSApp.delegate is weak)
var appDelegate = AppDelegate()

NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.delegate = appDelegate

// MARK: - Main Menu
let mainMenu = NSMenu()

let appItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(NSMenuItem(title: "Acerca de MacDevUtils",
                            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                            keyEquivalent: ""))
appMenu.addItem(.separator())
appMenu.addItem(NSMenuItem(title: "Salir de MacDevUtils",
                            action: #selector(NSApplication.terminate(_:)),
                            keyEquivalent: "q"))
appItem.submenu = appMenu
mainMenu.addItem(appItem)

let editItem = NSMenuItem()
let editMenu = NSMenu(title: "Edición")
editMenu.addItem(NSMenuItem(title: "Deshacer",      action: Selector(("undo:")),                      keyEquivalent: "z"))
editMenu.addItem(NSMenuItem(title: "Rehacer",       action: Selector(("redo:")),                      keyEquivalent: "Z"))
editMenu.addItem(.separator())
editMenu.addItem(NSMenuItem(title: "Cortar",        action: #selector(NSText.cut(_:)),              keyEquivalent: "x"))
editMenu.addItem(NSMenuItem(title: "Copiar",        action: #selector(NSText.copy(_:)),             keyEquivalent: "c"))
editMenu.addItem(NSMenuItem(title: "Pegar",         action: #selector(NSText.paste(_:)),            keyEquivalent: "v"))
editMenu.addItem(NSMenuItem(title: "Seleccionar todo", action: #selector(NSText.selectAll(_:)),     keyEquivalent: "a"))
editItem.submenu = editMenu
mainMenu.addItem(editItem)

NSApplication.shared.mainMenu = mainMenu
NSApplication.shared.run()
