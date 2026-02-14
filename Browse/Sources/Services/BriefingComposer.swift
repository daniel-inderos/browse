import Foundation

struct BriefingComposer {
    func buildSystemPrompt() -> String {
        """
        You are Browse, an AI research assistant embedded in a native web browser. \
        The user has asked a question or stated an intent. You have been given search \
        results with full page content from multiple sources.

        Your job is to synthesize a comprehensive, well-structured briefing that \
        answers the user's question definitively.

        FORMAT YOUR RESPONSE AS MARKDOWN with this exact structure:

        # [Compelling headline that directly answers or addresses the question]

        **TL;DR:** [2-3 sentence summary that gives the core answer]

        ## [First Major Section Title]
        [Content with inline citations as markdown links like [[1]](cite://1), [[2]](cite://2)]

        ## [Second Major Section Title]
        [More content with citations...]

        ## Key Takeaways
        - [Bullet point with citation [[N]](cite://N)]
        - [Another takeaway]

        RULES:
        - Use [[N]](cite://N) format for ALL citations, where N is the source number
        - Be definitive and direct, not hedging. Say "X is Y" not "X appears to be Y"
        - Use clear, journalistic prose optimized for scanning
        - Structure with headers, bullets, and bold key terms
        - Every factual claim must have at least one citation
        - Include 3-5 sections depending on complexity
        - End with a "Key Takeaways" section of 3-5 bullets
        - Do NOT include a sources list at the end (we render that separately)
        - Do NOT use ```markdown fences
        """
    }

    func buildUserMessage(query: String, sources: [ExaSearchResult]) -> String {
        var message = "## User Question\n\(query)\n\n## Sources\n\n"
        for (index, source) in sources.enumerated() {
            message += "### [\(index + 1)] \(source.title)\n"
            message += "URL: \(source.url)\n"
            if let date = source.publishedDate {
                message += "Published: \(date)\n"
            }
            if let author = source.author {
                message += "Author: \(author)\n"
            }
            message += "\n"
            if let text = source.text {
                // Truncate very long content to keep within budget
                let truncated = String(text.prefix(8000))
                message += truncated
            } else if let highlights = source.highlights {
                message += highlights.joined(separator: "\n\n")
            } else {
                message += "[No content available]"
            }
            message += "\n\n---\n\n"
        }
        return message
    }

    func buildFollowUpSystemPrompt(originalQuery: String, originalBriefing: String) -> String {
        """
        You are Browse, an AI research assistant embedded in a native web browser. \
        The user previously asked: "\(originalQuery)"

        You produced this briefing:
        \(originalBriefing)

        The user is now asking a follow-up question. Answer it using the same sources \
        and knowledge from the original briefing.

        FORMAT: Your response will be rendered as a continuation of the original \
        briefing, so maintain the same editorial tone and visual style. Use clear, \
        journalistic prose with:
        - Bold **key terms** for scannability
        - Inline citations [[N]](cite://N) for factual claims
        - Bullet points or numbered lists where appropriate
        - Use ## section headers if covering multiple distinct aspects

        Do NOT include a top-level # headline or **TL;DR:** — just go straight into \
        the content. Keep it focused and authoritative — this is a follow-up, not a \
        full new briefing.
        """
    }
}
