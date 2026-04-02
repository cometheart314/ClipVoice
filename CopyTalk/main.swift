import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// メインメニューを作成（Edit メニューの Cut/Copy/Paste を有効にするため）
let mainMenu = NSMenu()

let appMenuItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit CopyTalk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)

let editMenuItem = NSMenuItem()
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
editMenu.addItem(NSMenuItem.separator())
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editMenuItem.submenu = editMenu
mainMenu.addItem(editMenuItem)

app.mainMenu = mainMenu
app.run()
