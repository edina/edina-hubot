# Description:
#   Digimap Continuous Integration script.
#   This script handles the integration of Hubot and Jenkins.
#
# Commands:
#   hubot: dmci deploy <app> <version> <destination> - Tell Jenkins what to deploy and where.
#   hubot: dmci release <app>                        - Tell Jenkins what to run the Maven Release Plugin for <app>.
#
# Variables:
#   HUBOT_MVN_REPO_URL - Url to Maven Repository (including trailing slash).
#   HUBOT_JENKINS_AUTH_TOKENS - String representation of uun/token pairs e.g.
# {"user1":"User's Jenkins auth token","user2":"User's Jenkins auth token"}
# You can get the auth token from $JENKINS_URL/me/configure when logged into Jenkins.
#
# Author:
#   marksmall

xml2js = require('xml2js')
xmlParser = new xml2js.Parser()
moment = require('moment')

mavenRepository = process.env.HUBOT_MVN_REPO_URL

authTokensString = process.env.HUBOT_JENKINS_AUTH_TOKENS
authTokens = JSON.parse(authTokensString)

sites = ['DEV', 'BETA', 'KB', 'AT']

apps =
  services:
    location: 'edina/service/'
    groupId: 'edina.service'
    apps: ['clive', 'gistranslation', 'logger', 'scheduler']
  frontend:
    location: 'edina/digimap/'
    groupId: 'edina.digimap'
    apps: ['cdptquery', 'codepoint', 'datadownload', 'digiadmin', 'gaz-plus', 'gaz-simple', 'interface', 'mapproxy', 'marinelexicon', 'roam', 'siterep']


getParams = (args, res, callback) ->
  params = args.split(' ')

  app = null
  groupId = null
  for element in apps.frontend.apps
    if element == params[0]
      app = element
      groupId = apps.frontend.groupId
      location = apps.frontend.location

  if app == null
    for element in apps.services.apps
      if element == params[0]
        app = element
        groupId = apps.services.groupId
        location = apps.services.location

  if app == null
    msg = 'Error: The app requested doesn\'t match any known'
    res.reply msg
  else
    # Has site been supplied? i.e. DEV|BETA|KB|AT
    # I not ddefault to beta.
    # Check this before version since this has a limited number of options.
    # First check the second supplied parmeter.
    site = null
    isParamSite = false
    if params[1] in sites
      site = params[1]
      isParamSite = true

    if site == null
      if params[2] in sites
        site = params[2]
      else
        site = 'BETA'

    # Has version been supplied?
    # User's could get params in wrong order e.g. roam DEV 1.1, instead of roam 1.1 DEV
    # It is possible for version to be undefined, we will check and use latest if so.
    if isParamSite
      version = params[2]
    else
      version = params[1]

    options =
      artifactId: app
      groupId: groupId
      version: version
      location: location
      site: site

    callback options

getMetadata = (params, res, callback) ->
  # Construct URL to get app's maven metadata.
  metadataUrl = "#{mavenRepository}#{params.location}#{params.artifactId}/maven-metadata.xml"
  # console.log("METADATA: #{metadataUrl}")
  # Get metadata and get deploy params.
  res.http(metadataUrl).get() (error, response, body) ->
    if error
      res.reply "Error: #{error}"
      return

    switch response.statusCode
      when 200
        # Convert XML to JSON.
        xmlParser.parseString body, (err, result) ->
          if err
            res.reply "Error Parsing Response: #{err}"
            return
          # res.reply "Error Parsing Response: #{err}" if err?

          metadata = extractMetadata(result.metadata)

          callback metadata
      else
        console.log "NON 200 Response: #{response.statusCode}"
        res.reply "ERROR Getting Maven Metadata from #{metadataUrl}: #{error}"
        return


# Extract metadata from maven-metadata request.
extractMetadata = (data) ->
  versioning = data.versioning[0]

  # Get latest version either SNAPSHOT or RELEASE.
  versions = versioning.versions[0].version

  # Get last updated timestamp.
  lastUpdatedStr = versioning.lastUpdated[0]
  latestDate = moment(lastUpdatedStr, 'YYYYMMDDhhmmss')

  latestVersion: versions[versions.length-1]

  # Get latest RELEASE.
  latestRelease: versioning.release[0]

  # Format last updated timestamp.
  latestUpdated: latestDate.format('YYYY-MM-DD hh:mm:ss')


# Get Jenkins deploy job parameters.
# If params are provided, use them, otherwise use defaults.
#
# params  - parameters sent in deploy request to bot
# metadata - parameters from maven metadata for the app.
getDeployParams = (params, metadata) ->
  app: params.app
  groupId: params.groupId
  version: params.version ? metadata.latestVersion
  site: params.location ? 'beta'


executeJob = (url, params, res, job) ->
  #console.log "URL: #{url}"
  paramsString = JSON.stringify params
  #console.log "PARAMS: #{paramsString}"
  token = params.token
  #console.log "TOKEN: #{token}"
  json = params.json
  app = null
  for param in json.parameter
    console.log "param: #{param.name}"
    if param.name == 'ARTIFACT_ID'
      console.log "app: #{param.value}"
      app = param.value
  
  jsonString = JSON.stringify json
  #console.log "JSON: #{jsonString}"
  encodedJson = encodeURIComponent jsonString
  #console.log "ENCODED JSON: #{encodedJson}"

  # If job is release, need to get the releaseVersion and developmentVersion 
  data = ''
  if token == 'release'
    for k, v of json
      console.log "RELEASE PARAM: #{k}, value: #{v}"
      if k == 'releaseVersion'
        data += "releaseVersion=#{v}"
      if k == 'developmentVersion'
        data += "&developmentVersion=#{v}&"

  data += "token=#{token}&json=#{encodedJson}"
  console.log "DATA: #{data}"


  buffer = new Buffer "msmall1:9c460057fb59d1e8c2d0ba79229ecf8c"
  authorization = "Basic " + buffer.toString 'base64'

  res.http(url)
    .header('Content-Type', 'application/x-www-form-urlencoded')
    .header('Authorization', "authorization")
    .post(data) (error, response, body) ->
      if error
        res.reply "Error: #{error}"
        return

      switch response.statusCode
        when 201
          # console.log "Request Successful"
          res.reply "Completed #{token} of #{app}"
        when 302
          # console.log "Request Successful"
          res.reply "Completed #{token} of #{app}"
        else
          console.log "ERROR Response: #{response.statusCode}"
          res.reply "ERROR Executing Jenkins Job: #{error}"
          return

getUserToken = (user) ->
  token = null
  for key, value of authTokens
    if user == key
      # console.log "User: #{user} auth token: #{value}"
      token = value

  token: token


module.exports = (robot) ->
  robot.respond /dmci deploy(.*)$/i, (res) ->
    # Check if user is permitted.
    user = res.message.user.name
    token = getUserToken user
    if token.token == null
      res.reply "Error: User @#{user} is not permitted to deploy apps"
      return

    # console.log "GETTING DEPLOY PARAMS"
    # Trim whitespace.
    args = res.match[1].replace /^\s+|\s+$/g, ''
    if args.length < 1
      msg = 'Error: no args, need at least the name of the app to deploy'
      res.reply msg
      return
    else
      getParams args, res, (params) ->
        options =
          token: 'deploy'
          json:
            parameter: [
              {
                name: 'GROUP_ID'
                value: params.groupId
              }
              {
                name: 'ARTIFACT_ID'
                value: params.artifactId
              }
              {
                name: 'VERSION'
                value: params.version
              }
              {
                name: 'SITE'
                value: params.site
              }
            ]

        url = "https://#{user}:#{token.token}@geodev.edina.ac.uk/jenkins/job/dm-deploy/build"
        # Check if version was defined, if so, use it, else get latest from
        # maven metadata.
        if params.version?
          # Request Jenkins job run.
          executeJob url, options, res, 'deploy'
          # depParams = JSON.stringify params, null, 2
          # console.log "PARAM: #{depParams}"
          msg = "Deploying #{params.artifactId} v#{params.version} to #{params.site}"
          res.reply msg
          return
        else
          metadata = getMetadata params, res, (metadata) ->
            version = null
            for key, param of options.json.parameter
              if param.name == 'VERSION'
                version = metadata.latestVersion
                param.value = metadata.latestVersion

            # Request Jenkins job run.
            executeJob url, options, res, 'deploy'
            # depParams = JSON.stringify params, null, 2
            # console.log "PARAMS: #{depParams}"
            msg = "Deploying #{params.artifactId} v#{version} to #{params.site}"
            res.reply msg
            return

  robot.respond /dmci release(.*)$/i, (res) ->
    # Check if user is permitted.
    user = res.message.user.name
    token = getUserToken user
    if token.token == null
      res.reply "Error: User @#{user} is not permitted to release apps"
      return

    # Trim whitespace.
    args = res.match[1].replace /^\s+|\s+$/g, ''
    if args.length < 1
      msg = 'Error: no args, need the name of the app to release'
      res.reply msg
      return
    else
      getParams args, res, (params) ->
        getMetadata params, res, (metadata) ->
          releaseVersion = metadata.latestVersion.replace /-SNAPSHOT/, ''
          index = releaseVersion.indexOf '.'
          majorVersion = releaseVersion.substring 0, index
          # console.log "MAJOR VERSION: #{majorVersion}"
          minorVersion = releaseVersion.substring index + 1, releaseVersion.length
          minorVersion++
          # console.log "MINOR VERSION: #{minorVersion}"
          developmentVersion = "#{majorVersion}.#{minorVersion}-SNAPSHOT"

          index = params.groupId.indexOf '.'
          groupId = params.groupId.substring index + 1, params.groupId.length
          console.log "ROUPID: #{groupId}"

          options =
            token: 'release'
            releaseVersion: releaseVersion
            developmentVersion: developmentVersion
            json:
              releaseVersion: releaseVersion
              developmentVersion: developmentVersion
              isDryRun: false
              parameter: [
                {
                  name: 'GROUP_ID'
                  value: groupId
                }
                {
                  name: 'ARTIFACT_ID'
                  value: params.artifactId
                }
              ]

          # Request Jenkins job run.
          url = "https://#{user}:#{token.token}@geodev.edina.ac.uk/jenkins/job/dm-maven-release/m2release/submit"

          executeJob url, options, res, 'release'
          params.releaseVersion = metadata.latestVersion.replace /-SNAPSHOT/, ''

          msg = "Releasing #{params.artifactId} v#{params.releaseVersion}"
          res.reply msg
          return
