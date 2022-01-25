import jenkins.model.*
import org.jenkinsci.plugins.ghprb.*

GhprbTrigger.DescriptorImpl descriptor = Jenkins.instance.getDescriptorByType(org.jenkinsci.plugins.ghprb.GhprbTrigger.DescriptorImpl.class)

List<GhprbGitHubAuth> githubAuths = descriptor.getGithubAuth()

String serverAPIUrl = '%%GITHUB_API_URL%%'
String jenkinsUrl = '%%JENKINS_SERVER_URL%%'
String credentialsId = '%%CREDENTIAL_NAME%%'
String description = 'GitHub API connection'
String id = '%%CREDENTIAL_NAME%%'
String secret = null
githubAuths.add(new GhprbGitHubAuth(serverAPIUrl, jenkinsUrl, credentialsId, description, id, secret))

descriptor.save()
