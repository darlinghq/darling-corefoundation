# CFFileDescriptor

Build `cffiledescriptor.c` against CoreFoundation and run it under Darling with a timeout. It checks that read and write callbacks are delivered by a run loop, once per enabling, that invalidation invalidates the run loop source and closes the descriptor only when asked, and that the context is retained at creation and released at invalidation.

Before the change the program does not link: the `CFFileDescriptor` functions declared in the header have no implementation. After it, all checks pass.
