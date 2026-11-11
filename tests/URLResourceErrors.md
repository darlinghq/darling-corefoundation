# URL resource errors and links

Build URLResourceErrors.m against Foundation/CoreFoundation and run under Darling. Creates and removes its own mkdtemp directory. Twelve checks cover regular files/directories, links to both, dangling links, and failed supported-property requests with and without an NSError output. Modification date is used because file-size resource properties are currently unsupported.

Installed baseline: six failures; candidate: zero failures. No Apple application launch or PAC override is required.
