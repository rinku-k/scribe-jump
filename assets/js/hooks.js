let Hooks = {}

Hooks.Clipboard = {
    mounted() {
        this.handleEvent("copy-to-clipboard", ({ text: text }) => {
            navigator.clipboard.writeText(text).then(() => {
                this.pushEventTo(this.el, "copied-to-clipboard", { text: text })
                setTimeout(() => {
                    this.pushEventTo(this.el, "reset-copied", {})
                }, 2000)
            })
        })
    }
}

Hooks.ChatScroll = {
    mounted() {
        this.scrollToBottom()
        this.observer = new MutationObserver(() => {
            this.scrollToBottom()
        })
        this.observer.observe(this.el, { childList: true, subtree: true })
    },
    updated() {
        this.scrollToBottom()
    },
    destroyed() {
        if (this.observer) {
            this.observer.disconnect()
        }
    },
    scrollToBottom() {
        this.el.scrollTop = this.el.scrollHeight
    }
}

Hooks.ChatInput = {
    mounted() {
        this.autoResize();
        this.el.addEventListener("input", () => this.autoResize());

        this.el.addEventListener("keydown", (e) => {
            if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                // Find and trigger form submission
                const form = this.el.closest("form");
                if (form) {
                    if (typeof form.requestSubmit === "function") {
                        form.requestSubmit();
                    } else {
                        form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
                    }
                }
            }
        });

        // Handle server-side input value updates (e.g., after tagging a contact)
        this.handleEvent("update_chat_input", ({ value }) => {
            this.el.value = value;
            this.autoResize();
            // Refocus the input and move cursor to end after tagging a contact
            this.el.focus();
            this.el.setSelectionRange(value.length, value.length);
            // Notify server that input is focused (in case blur fired when clicking dropdown)
            this.pushEventTo(this.el, "input_focus", {});
        });
    },
    updated() {
        this.autoResize();
    },
    autoResize() {
        this.el.style.height = "auto";
        this.el.style.height = (this.el.scrollHeight) + "px";
    }
}

export default Hooks