# Description:
#   Digimap Continuous Integration script.
#   This script handles the integration of Hubot and Jenkins.
#
# Commands:
#   hubot: dmci deploy <app> <version> <site> - Deploy an  app (defaults: version=latest, site=beta).
#   hubot: dmci release <app> - Tell Jenkins what to run the Maven Release Plugin for <app>.
#   hubot: dmci update <days> - Update beta with apps deployed in last <days> (default 1 day).
#   hubot: dmci start update <days> <cron> - Deploy to beta, apps deployed <days> ago using cron syntax
#   hubot: dmci stop update - Stop any regular deploys to beta, if one has been set
#   hubot: dmci show update - Display information on a regular update to beta, if one has been set

xml2js = require('xml2js')
xmlParser = new xml2js.Parser()
moment = require('moment')
CronJob = require('cron').CronJob

mavenRepository = process.env.HUBOT_MVN_REPO_URL

authTokensString = process.env.HUBOT_JENKINS_AUTH_TOKENS
authTokens = JSON.parse(authTokensString)

# Defaults for the gort start update command. These will run the cron at 10pm
# every evening, and the update will look back 1 day for new apps to deploy to beta.
defaultStartUpdateDays = '1'
defaultStartUpdateCronLine = '0 0 22 * * *'

sites = ['DEV', 'BETA', 'KB', 'AT']

apps =
  services:
    location: 'edina/service/'
    groupId: 'edina.service'
    apps: ['clive', 'gistranslation', 'logger', 'scheduler', 'ordermaster']
  frontend:
    location: 'edina/digimap/'
    groupId: 'edina.digimap'
    apps: ['cdptquery', 'codepoint', 'datadownload', 'digiadmin', 'gaz-plus', 'gaz-simple', 'interface', 'mapproxy', 'marinelexicon', 'roam', 'siterep']

libraries =
  location: 'edina/digimap/'
  groupId: 'edina.digimap'
  apps: ['mapper-framework', 'user-persistence', 'authorisation', 'digimap-logging', 'coordomatic']

# Small helper function to get group ID for an app.
getGroupId = (app) ->
  if app in apps.services.apps
    return apps.services.groupId
  else
    return apps.frontend.groupId

# Get the list of builds from Jenkins (list passed to callback)
getBuildList = (res, callback) ->
  url = "https://geodev.edina.ac.uk/jenkins/job/dm-deploy/api/json"
  res.http(url)
    .get() (error, response, body) ->
      if error
        res.reply "getBuildList Error: #{error}"
        return
      json = JSON.parse body
      callback json.builds

# Get the info for the given build number (info passed to callback).
getBuildInfo = (res, buildNumber, callback) ->
  url = "https://geodev.edina.ac.uk/jenkins/job/dm-deploy/#{buildNumber}/api/json"
  res.http(url)
    .get() (error, response, body) ->
      if error
        res.reply "getBuildInfo Error: #{error}"
        return
      json = JSON.parse body
      params = json.actions[0].parameters
      info = { }
      # The GROUP_ID, ARTIFACT_ID, VERSION, and SITE
      info[params[i].name] = params[i].value for i in [0..3]
      info['success'] = json.result == 'SUCCESS'
      info['timestamp'] = moment(json.timestamp, 'x')
      info['number'] = json.number
      callback info

# Iterate through the builds list in reverse chronological order, from the most recent
# build to the oldest build. When initially called index should be 0 (the start of the
# builds list) and the dontDeploy object will be empty. The callback will be executed for
# each app which has been deployed to dev within the required time window, and which has
# not already been deployed to beta. Null will be passed to the callback when all such
# builds have been found.
getDevDeploys = (res, endTime, builds, index, dontDeploy, callback) ->
  # Check to make sure we're not at the end of the build list. If we are pass null to the
  # callback and end.
  if index < builds.length
    # Retrieve the info for the current build, specified by 'index'.
    getBuildInfo res, builds[index].number, (info) ->
      # Is this build within our time range? If not pass null to the callback and end.
      if endTime.isBefore(info.timestamp)
        if info.SITE == 'BETA' && info.success && !(info.ARTIFACT_ID of dontDeploy)
          # We've come accross a successful deploy to BETA. Add it to the "don't deploy" object
          # since we don't want to deploy an app which has already been deployed to beta.
          dontDeploy[info.ARTIFACT_ID] = info
        else if info.SITE == 'DEV' && info.success && !(info.ARTIFACT_ID of dontDeploy)
          # We've come accross a successful deploy to dev which is NOT in the don't deploy object.
          # Pass the build info to the callback. Once the callback has finished, add the
          # app to the don't deploy object so that we don't deploy the same app muliple times.
          callback info
          dontDeploy[info.ARTIFACT_ID] = info
        # Recursively call getDevDeploys, moving onto the next build in the list.
        getDevDeploys res, endTime, builds, index+1, dontDeploy, callback
      else
        callback null
  else
    callback null

# Deploys to beta any apps which have been deployed to dev over the last <days>
deployToBeta = (res, userInfo, days, endMessage) ->
  # We don't want to deploy any apps before endTime (e.g. if days = 1 we only look 1 day back).
  endTime = moment().subtract(days, 'days')
  # Get the list of builds, passed to the callback
  getBuildList res, (builds) ->
    # Look through the buils list for all deploys to dev finishing a endTime
    getDevDeploys res, endTime, builds, 0, {}, (info) ->
      if info?
        # We've got the info for an app which should be deployed to beta.
        options =
          token: 'deploy'
          json:
            parameter: [
              { name: 'GROUP_ID',    value: getGroupId info.ARTIFACT_ID }
              { name: 'ARTIFACT_ID', value: info.ARTIFACT_ID }
              { name: 'VERSION',     value: info.VERSION }
              { name: 'SITE',        value: 'BETA' }
            ]
        url = "https://#{userInfo.user}:#{userInfo.token}@geodev.edina.ac.uk/jenkins/job/dm-deploy/build"
        executeJob url, options, res, 'deploy'
      else
        setTimeout ->
          res.reply endMessage
        , 200


getParams = (args, res, allowLibraries, callback) ->
  params = args.split(' ')

  app = apps.frontend.apps.find (e) -> e == params[0]
  groupId = apps.frontend.groupId
  location = apps.frontend.location

  if not app?
    app = apps.services.apps.find (e) -> e == params[0]
    groupId = apps.services.groupId
    location = apps.services.location

  # Check also libraries if alowed by the caller
  if allowLibraries and not app?
    app = libraries.apps.find (e) -> e == params[0]
    groupId = libraries.groupId
    location = libraries.location

  if not app?
    if allowLibraries
      msg = 'Error: The app or library requested doesn\'t match any known'
    else
      msg = 'Error: The app requested doesn\'t match any known'
    res.reply msg
  else
    console.log "Site has been supplied"

    # The default site (environment) is beta.
    site = 'BETA'

    if params[1] && params[1].toUpperCase() in sites
      # When second parameter is the 'site' then take third parameter
      # as the version if it's available
      site = params[1].toUpperCase()
      if params[2]
        version = params[2]
    else if params[2] && params[2].toUpperCase() in sites
      # When third parameter is the 'site' the second parameter should be
      # the version
      site = params[2].toUpperCase()
      version = params[1]
    else if params[1] && params.length == 2
      # Otherwise treat any second parameter as the version
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
        # console.log "NON 200 Response: #{response.statusCode}"
        res.reply "ERROR Getting Maven Metadata from #{metadataUrl}: #{error}"
        return

isInt = (n) ->
  /^\d+$/.test(n)

explodeVersionNumber = (version) ->
  # Convert semantic version to object with major/minor/patch numbers
  v = version.split /\.|-/
  return {
    major: if v[0]? && isInt(v[0]) then parseInt(v[0]) else 0,
    minor: if v[1]? && isInt(v[1]) then parseInt(v[1]) else 0,
    patch: if v[2]? && isInt(v[2]) then parseInt(v[2]) else 0,
    snapshot: /-SNAPSHOT$/.test(version),
    full:  version
  }

getHighestVersion = (versions) ->
  # Extract the highest version number from a list of versions (each a string)
  cur = { major: 0, minor: 0, patch: 0, full: null }
  exploded = (explodeVersionNumber v for v in versions)
  (if ( v.major > cur.major ||
       (v.major == cur.major && v.minor >  cur.minor) ||
       (v.major == cur.major && v.minor == cur.minor && v.patch > cur.patch)) then cur = v) for v in exploded.reverse()
  cur

# Extract metadata from maven-metadata request.
extractMetadata = (data) ->
  versioning = data.versioning[0]

  # Get latest version either SNAPSHOT or RELEASE.
  versions = versioning.versions[0].version

  # Get last updated timestamp.
  lastUpdatedStr = versioning.lastUpdated[0]
  latestDate = moment(lastUpdatedStr, 'YYYYMMDDhhmmss')

  last = getHighestVersion versions
  console.log "Highest Version: #{last.full}"

  latestVersion: last.full

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
  console.log "PARAMS: #{paramsString}"
  token = params.token
  #console.log "TOKEN: #{token}"
  json = params.json
  app = null
  for param in json.parameter
    # console.log "param: #{param.name}"
    if param.name == 'ARTIFACT_ID'
      # console.log "app: #{param.value}"
      app = param.value

  jsonString = JSON.stringify json
  #console.log "JSON: #{jsonString}"
  encodedJson = encodeURIComponent jsonString
  #console.log "ENCODED JSON: #{encodedJson}"

  # If job is release, need to get the releaseVersion and developmentVersion
  data = ''
  if token == 'release'
    for k, v of json
      # console.log "RELEASE PARAM: #{k}, value: #{v}"
      if k == 'releaseVersion'
        data += "releaseVersion=#{v}"
      if k == 'developmentVersion'
        data += "&developmentVersion=#{v}&"

  data += "token=#{token}&json=#{encodedJson}"
  # console.log "DATA: #{data}"

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
          # console.log "ERROR Response: #{response.statusCode}"
          res.reply "ERROR Executing Jenkins Job: #{error}"
          return

getUserToken = (user) ->
  token = null
  for key, value of authTokens
    if user == key
      # console.log "User: #{user} auth token: #{value}"
      token = value

  token: token

# Returns user and token information if user is permitted, or null otherwise.
getValidUser = (res) ->
  user = res.message.user.name
  token = getUserToken user
  if token.token == null
    res.reply "Error: User @#{user} is not permitted to release apps"
    return null
  else
    return { user: user, token: token.token }


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
      # Get parameters ignoring libraries (cannot deploy a library)
      getParams args, res, false, (params) ->
        console.log "Gotten Params: #{params.site}"
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
          console.log "Job Params: #{params.site}"
          executeJob url, options, res, 'deploy'
          # depParams = JSON.stringify params, null, 2
          # console.log "PARAM: #{depParams}"
          msg = "Starting deploy of #{params.artifactId} v#{params.version} to #{params.site}"
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
            console.log "Job Params from metadata: #{params.site}"
            executeJob url, options, res, 'deploy'
            # depParams = JSON.stringify params, null, 2
            # console.log "PARAMS: #{depParams}"
            msg = "Starting deploy of #{params.artifactId} v#{version} to #{params.site}"
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
      # Get the parameters including libraries (a library can be released)
      getParams args, res, true, (params) ->
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
          # console.log "GROUPID: #{groupId}"

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
          releaseVersion = metadata.latestVersion.replace /-SNAPSHOT/, ''

          msg = "Starting release of #{params.artifactId} v#{releaseVersion}"
          res.reply msg
          return

  robot.respond /dmci update(.*)$/, (res) ->
    days = parseInt (res.match[1].replace /^\s+|\s+$/g, '')
    if isNaN(days)
      days = 1
    userInfo = getValidUser res
    if userInfo?
      res.reply "Deploying apps to beta, looking back #{days} days"
      deployToBeta res, userInfo, days, "Update command completed, all job requests sent to Jenkins. Note that Jenkins jobs can fail"

  betaCronJob = null

  robot.respond /dmci start update\s*([0-9]*)\s*(.*)$/, (res) ->
    days = res.match[1]
    cronLine = res.match[2]
    userInfo = getValidUser res
    if userInfo?
      if betaCronJob?
        res.reply "Error: a regular deploy to beta job already exists"
      else
        try
          days = defaultStartUpdateDays if days == ''
          cronLine = defaultStartUpdateCronLine if cronLine == ''
          res.reply "Starting regular deploys to beta, looking back #{days} days with cron line '#{cronLine}'"
          cronJob = new CronJob cronLine, () ->
            res.reply "Auto deploying apps to beta, looking back #{days} days"
            deployToBeta res, userInfo, days, "Regular update completed, all job requests sent to Jenkins. Note that Jenkins jobs can fail"
          , null, true, 'Europe/London'
          betaCronJob = { 'days': days, 'cronLine': cronLine, 'cronJob': cronJob }
          cronJob.start()
        catch ex
          res.reply "Problem creating the cron job: is your cron line (#{cronLine}) valid?"

  robot.respond /dmci stop update/, (res) ->
    if (getValidUser res)?
      if betaCronJob?
        res.reply "Stopping regular deploy to beta which looked back #{betaCronJob.days} days with cron line #{betaCronJob.cronLine}"
        betaCronJob.cronJob.stop()
        betaCronJob = null
      else
        res.reply "Error: no regular deploy to beta created"

  robot.respond /dmci show update/, (res) ->
    if (getValidUser res)?
      if betaCronJob?
        res.reply "Regular deploy to beta looking back #{betaCronJob.days} days with cron line #{betaCronJob.cronLine}"
      else
        res.reply "No regular deploy to beta exists"
