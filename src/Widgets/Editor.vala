/**
 * MIT License
 *
 * Copyright (c) 2022 TwiRpin Around
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

using LinkGrammar;

namespace TwiRpin {
    public class Editor : GtkSource.View {
        private Markdown markdown_enrichment;
        private GrammarChecker grammar_enrichment;

        construct {
            // Get a pointer to the Markdown Language
            var manager = GtkSource.LanguageManager.get_default ();
            var language = manager.guess_language (null, "text/markdown");

            // Set language to markdown
            buffer = new GtkSource.Buffer.with_language (language);
            set_wrap_mode (Gtk.WrapMode.WORD);

            // Attach markdown enrichment
            markdown_enrichment = new Markdown ();
            markdown_enrichment.attach (this);

            // Attack grammar checker
            grammar_enrichment = new GrammarChecker ();
            grammar_enrichment.attach (this);

            Timeout.add (250, () => {
                markdown_enrichment.recheck_all ();
                grammar_enrichment.recheck_all ();
                return false;
            });

            // Sign up for updates
            buffer.changed.connect (() => {
                markdown_enrichment.recheck_all ();
                grammar_enrichment.recheck_all ();
            });

            destroy.connect (() => {
                markdown_enrichment.detach ();
                grammar_enrichment.detach ();
            });
        }
    }
}