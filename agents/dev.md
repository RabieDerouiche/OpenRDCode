---
description: "Implementation agent of the workflow commands (/dev, /cqrs, /apply-pattern, /extract-pattern): the build agent without the MCP tools, so that each request stays small. Delegates the unit tests of a step to test-writer."
mode: all
hidden: true
temperature: 1.0
top_p: 0.95
permission: { task: { "*": deny, "test-writer": allow, "debugger": allow, "architect": allow }, "*jira*": deny, "*Jira*": deny, "*JIRA*": deny, "*confluence*": deny, "*Confluence*": deny, "*gitlab*": deny, "*GitLab*": deny, "*Gitlab*": deny, "*sonar*": deny, "*Sonar*": deny, "*fortify*": deny, "*Fortify*": deny, "*kibana*": deny, "*Kibana*": deny, "*elastic*": deny, "*Elastic*": deny }
---
