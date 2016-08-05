Helper = require('hubot-test-helper')
expect = require('chai').expect
nock = require('nock')
Promise = require('bluebird')
co = require('co')


process.env.HUBOT_MVN_REPO_URL = 'https://geodev.edina.ac.uk/maven-repository/'
authTokens =
  user: 'token'
process.env.HUBOT_JENKINS_AUTH_TOKENS = JSON.stringify(authTokens)

# helper loads a specific script if it's a file
helper = new Helper('../scripts/digimap-ci.coffee')

describe 'digimap-ci', ->
  room = null
  mockXml = '<?xml version="1.0" encoding="UTF-8"?>
<metadata>
<groupId>edina.digimap</groupId>
<artifactId>roam</artifactId>
<versioning>
<release>2.31.1</release>
<versions>
<version>2.20.1</version>
<version>2.21-SNAPSHOT</version>
<version>2.21</version>
<version>2.22-SNAPSHOT</version>
<version>2.22</version>
<version>2.23-SNAPSHOT</version>
<version>2.23</version>
<version>2.24-SNAPSHOT</version>
<version>2.25-SNAPSHOT</version>
<version>2.24</version>
<version>2.25</version>
<version>2.26-SNAPSHOT</version>
<version>2.27-SNAPSHOT</version>
<version>2.26</version>
<version>2.27</version>
<version>2.28-SNAPSHOT</version>
<version>2.29-SNAPSHOT</version>
<version>2.29</version>
<version>2.30-SNAPSHOT</version>
<version>2.30</version>
<version>2.31-SNAPSHOT</version>
<version>2.30.2</version>
<version>2.31</version>
<version>2.32-SNAPSHOT</version>
<version>2.31.1</version>
</versions>
<lastUpdated>20160511142327</lastUpdated>
</versioning>
</metadata>'

  deployResponse = '{
    "builds" : [
        {
          "number" : 574,
          "url" : "https://geodev.edina.ac.uk/jenkins/job/dm-deploy/574/"
        },
        {
          "number" : 573,
          "url" : "https://geodev.edina.ac.uk/jenkins/job/dm-deploy/573/"
        },
        {
          "number" : 572,
          "url" : "https://geodev.edina.ac.uk/jenkins/job/dm-deploy/572/"
        },
        {
          "number" : 571,
          "url" : "https://geodev.edina.ac.uk/jenkins/job/dm-deploy/571/"
        }
      ]
    }'

  timeNow = new Date().getTime()
  oneHour = 60*60*1000

  deployBuildResposes =
    574: "{
            \"actions\" : [
             {
               \"parameters\" : [
                 { \"name\" : \"GROUP_ID\", \"value\" : \"edina.digimap\" },
                 { \"name\" : \"ARTIFACT_ID\", \"value\" : \"siterep\" },
                 { \"name\" : \"VERSION\", \"value\" : \"2.1-SNAPSHOT\" },
                 { \"name\" : \"SITE\", \"value\" : \"DEV\" }
               ]
             }
           ],
           \"result\" : \"SUCCESS\",
           \"timestamp\" : #{timeNow},
           \"number\" : 574
         }",
    573: "{
           \"actions\" : [
             {
               \"parameters\" : [
                 { \"name\" : \"GROUP_ID\", \"value\" : \"edina.service\" },
                 { \"name\" : \"ARTIFACT_ID\", \"value\" : \"clive\" },
                 { \"name\" : \"VERSION\", \"value\" : \"1.25-SNAPSHOT\" },
                 { \"name\" : \"SITE\", \"value\" : \"BETA\" }
               ]
             }
           ],
           \"number\" : 573,
           \"result\" : \"SUCCESS\",
           \"timestamp\" : #{timeNow - oneHour}
         }",
    572: "{
           \"actions\" : [
             {
               \"parameters\" : [
                 { \"name\" : \"GROUP_ID\", \"value\" : \"edina.service\" },
                 { \"name\" : \"ARTIFACT_ID\", \"value\" : \"clive\" },
                 { \"name\" : \"VERSION\", \"value\" : \"dev\" },
                 { \"name\" : \"SITE\", \"value\" : \"DEV\" }
               ]
             }
           ],
           \"number\" : 572,
           \"result\" : \"SUCCESS\",
           \"timestamp\" : #{timeNow - (2*oneHour)}
         }",
    571: "{
           \"actions\" : [
             {
               \"parameters\" : [
                 { \"name\" : \"GROUP_ID\", \"value\" : \"edina.service\" },
                 { \"name\" : \"ARTIFACT_ID\", \"value\" : \"ordermaster\" },
                 { \"name\" : \"VERSION\", \"value\" : \"3.16-SNAPSHOT\" },
                 { \"name\" : \"SITE\", \"value\" : \"DEV\" }
               ]
             }
           ],
           \"number\" : 571,
           \"result\" : \"SUCCESS\",
           \"timestamp\" : #{timeNow - (25*oneHour)}
         }"

  beforeEach ->
    room = helper.createRoom()

  afterEach ->
    room.destroy()
    nock.cleanAll()


  context 'Invalid user tells Hubot to deploy an app', ->
    msg = 'hubot dmci deploy roam'

    beforeEach ->
      room.user.say 'user1', msg

    it 'should reply with error message, user is not permitted to deploy apps', ->
      expect(room.messages).to.eql [
        ['user1', msg]
        ['hubot', '@user1 Error: User @user1 is not permitted to deploy apps']
      ]

  context 'user tells Hubot to deploy with no parameters', ->
    msg = 'hubot dmci deploy'

    beforeEach ->
      room.user.say 'user', msg

    it 'should reply with error message, need name of app', ->
      expect(room.messages).to.eql [
        ['user', msg]
        ['hubot', '@user Error: no args, need at least the name of the app to deploy']
      ]

  context 'user tells Hubot to deploy an app that doesn\'t exist', ->
    msg = 'hubot dmci deploy nothing'

    beforeEach ->
      room.user.say 'user', msg

    it 'should reply with error message, app name doesn\'t exist', ->
      expect(room.messages).to.eql [
        ['user', msg]
        ['hubot', '@user Error: The app requested doesn\'t match any known']
      ]

  context 'user tells Hubot to deploy an app', ->
    msg = 'hubot dmci deploy roam 1.1 DEV'

    beforeEach ->
      do nock.disableNetConnect
      user = 'user'
      token = 'token'
      nock("https://#{user}:#{token}@geodev.edina.ac.uk")
        .post('/jenkins/job/dm-deploy/build')
        .reply 201, ''

      room.user.say 'user', msg

    it 'should reply: Deploying roam v1.1 to DEV', ->
      expect(room.messages).to.eql [
        ['user', msg]
        ['hubot', '@user Deploying roam v1.1 to DEV']
        ['hubot', '@user Completed deploy of roam']
      ]

  context 'user tells Hubot to deploy an app that doesn\'t contain version or destination', ->
    msg = 'hubot dmci deploy roam'
    beforeEach ->
      do nock.disableNetConnect
      nock('https://geodev.edina.ac.uk')
        .get('/maven-repository/edina/digimap/roam/maven-metadata.xml')
        .reply 200, mockXml

      user = 'user'
      token = 'token'
      nock("https://#{user}:#{token}@geodev.edina.ac.uk")
        .post('/jenkins/job/dm-deploy/build')
        .reply 201, ''

      room.user.say 'user', msg

    it 'should reply: Deploying roam v2.32-SNAPSHOT to BETA', ->
      expect(room.messages).to.eql [
        ['user', msg]
        ['hubot', '@user Deploying roam v2.32-SNAPSHOT to BETA']
        ['hubot', '@user Completed deploy of roam']
      ]

  context 'user tells Hubot to deploy an app that doesn\'t contain version', ->
    msg = 'hubot dmci deploy roam DEV'

    beforeEach ->
      do nock.disableNetConnect
      nock('https://geodev.edina.ac.uk')
        .get('/maven-repository/edina/digimap/roam/maven-metadata.xml')
        .reply 200, mockXml

      user = 'user'
      token = 'token'
      nock("https://#{user}:#{token}@geodev.edina.ac.uk")
        .post('/jenkins/job/dm-deploy/build')
        .reply 201, ''

      room.user.say 'user', msg

    it  'should reply: Deploying roam v2.32-SNAPSHOT to DEV', ->
      expect(room.messages).to.eql [
        ['user', msg]
        ['hubot', '@user Deploying roam v2.32-SNAPSHOT to DEV']
        ['hubot', '@user Completed deploy of roam']
      ]

  context 'user tells Hubot to deploy an app that doesn\'t contain destination', ->
    msg = 'hubot dmci deploy roam 1.1'

    beforeEach ->
      do nock.disableNetConnect
      nock('https://geoDEV.edina.ac.uk')
        .get('/maven-repository/edina/digimap/roam/maven-metadata.xml')
        .reply 200, mockXml

      user = 'user'
      token = 'token'
      nock("https://#{user}:#{token}@geodev.edina.ac.uk")
        .post('/jenkins/job/dm-deploy/build')
        .reply 201, ''

      room.user.say 'user', msg

    it  'should reply: Deploying roam v1.1 to BETA', ->
      expect(room.messages).to.eql [
        ['user', msg]
        ['hubot', '@user Deploying roam v1.1 to BETA']
        ['hubot', '@user Completed deploy of roam']
      ]

  context 'Invalid user tells Hubot to release an app', ->
    msg = 'hubot dmci release roam'

    beforeEach ->
      room.user.say 'user1', msg

    it 'should reply with error message, user is not permitted to release apps', ->
      expect(room.messages).to.eql [
        ['user1', msg]
        ['hubot', '@user1 Error: User @user1 is not permitted to release apps']
      ]

  context 'user tells Hubot to release with no parameters', ->
    msg = 'hubot dmci release'

    beforeEach ->
      room.user.say 'user', msg

    it  'should reply with error message, need name of app', ->
      expect(room.messages).to.eql [
        ['user', msg]
        ['hubot', '@user Error: no args, need the name of the app to release']
      ]

  context 'user tells Hubot to release with unknown app name parameter', ->
    msg = 'hubot dmci release nothing'

    beforeEach ->
      room.user.say 'user', msg

    it  'should reply with error message, app name doesn\'t exist', ->
      expect(room.messages).to.eql [
        ['user', msg]
        ['hubot', '@user Error: The app requested doesn\'t match any known']
      ]

  context 'user tells Hubot to release an app', ->
    msg = 'hubot dmci release roam'

    beforeEach ->
      do nock.disableNetConnect
      nock('https://geodev.edina.ac.uk')
        .get('/maven-repository/edina/digimap/roam/maven-metadata.xml')
        .reply 200, mockXml

      user = 'user'
      token = 'token'
      nock("https://#{user}:#{token}@geodev.edina.ac.uk")
        .post('/jenkins/job/dm-maven-release/m2release/submit')
        .reply 302, ''

      room.user.say 'user', msg

    it  'should reply: Releasing roam v2.32', ->
      expect(room.messages).to.eql [
        ['user', msg]
        ['hubot', '@user Releasing roam v2.32']
        ['hubot', '@user Completed release of roam']
      ]

  context 'user tells Hubot to update dev to beta over last day', ->
    msg = 'hubot dmci update dev to beta 1'

    nock.emitter.on 'no match', (req) ->
      console.log("emmitter:", req)

    beforeEach ->
      do nock.disableNetConnect
      nock('https://geodev.edina.ac.uk')
        .get('/jenkins/job/dm-deploy/api/json')
        .reply 200, deployResponse

      for buildNumber in [571..574]
        nock('https://geodev.edina.ac.uk')
          .get("/jenkins/job/dm-deploy/#{buildNumber}/api/json")
          .reply 200, deployBuildResposes[buildNumber]

      user = 'user'
      token = 'token'
      nock("https://#{user}:#{token}@geodev.edina.ac.uk")
        .post('/jenkins/job/dm-deploy/build')
        .reply 201, ''

      # Needed to introduce a delay between the message and checking
      # the output state. Anything more than 2 seconds will fail.
      co =>
        yield room.user.say 'user', msg
        yield new Promise.delay(500)

    it 'should reply: Deploying apps to beta, looking back 1 days', ->
      expect(room.messages).to.eql [
        ['user', msg]
        ['hubot', '@user Deploying apps to beta, looking back 1 days']
        ['hubot', '@user Completed deploy of siterep']
        ['hubot', '@user All apps deployed to beta']
      ]
