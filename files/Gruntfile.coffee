# CommonJS module pattern
module.exports = (grunt) ->

  # some configuration for our test suite compilation
  config =
    # we're storing everything in ./.mocha/
    tmpDir: ".mocha"
    # mocha.yml lists dependencies for the specrunner
    mocha: grunt.file.readYAML("test/javascripts/mocha.yml")
    # We build a spec runner from a template, so we don't have to hard-code
    # changes
    specRunnerTemplate: grunt.file.read("test/javascripts/SpecRunner.html.tmpl")
    # the destination of our spec runner:
    specRunner: ".mocha/index.html"
    # We're going to run our tests on a little server at http://localhost:8000
    server:
      port: 8000
      base: "."
      hostname: "localhost"
    # locations and globs for app source, tests, and templates
    app:
      root: "app/assets/javascripts"
      glob: "**/*.coffee"
    tests:
      root: "test/javascripts"
      glob: "**/*.coffee"
    templates:
      root: "app/assets/templates"
      glob: "**/*.ejs"
    # used to track wheter we're running in the browser or the console
    runningIn: null

  # LoDash
  _ = grunt.util._

  # Helper used to get a list of compiled tests
  testModuleNames = ->
    files = grunt.file.glob.sync("#{config.tmpDir}/tests/**/*.js")
    _.map( files, (file) -> file.match(///#{config.tmpDir}/(.*)\.js$///)[1] )

  # generates pathnames for our JST templates.
  templatePathFor = (filepath) ->
    pattern = ///#{config.templates.root}/(.*?)$///
    "/"+filepath.match(pattern)[1]

  # Creates a converter function that does:
  # source/path/to.coffee -> destination/path/to.js 
  relativeJsPath = (root) ->
    (destBase,destPath) ->
      pattern = ///^#{root}/(.*?)\.coffee$///
      destBase+destPath.replace(pattern, ($0, $1) -> "#{$1}.js" )

  # given a root, glob, and destination path, creates a map of destination/src
  # files.  E.g.:
  # expandedMapping('app/assets/javascripts', '**/*.coffee', '.mocha')
  #   => {
  #    "helpers/UserHelper.js": "app/assets/javascripts/helpers/UserHelper.coffee"
  #    "models/User.js": "app/assets/javascripts/models/User.coffee"
  #   }
  expandedMapping = (root, glob, destination) ->
    grunt.file.expandMapping(
      ["#{root}/#{glob}"],
      "#{destination}/",
      rename: relativeJsPath(root)
    )

  # Begin our Grunt configuration
  grunt.initConfig

    clean: 
      app: [
        "#{config.tmpDir}/**/*",
        "!#{config.tmpDir}/tests",        # ignore tests
        "!#{config.tmpDir}/tests/**",     #        test files
        "!#{config.tmpDir}/templates.js"  #        and templates
      ]
      tests: [config.specRunner, "#{config.tmpDir}/tests"]
      templates: ["#{config.tmpDir}/templates.js"]

    # using coffeelint to enforce some code quality
    coffeelint:
      options:
        no_trailing_whitespace: {level: 'error'}
        no_throwing_strings: {level: 'ignore'}
        max_line_length: {level: 'warn'}
      app: [config.app.root, config.app.glob].join('/')
      tests: [config.tests.root, config.tests.glob].join('/')

    # CoffeeScript compiler
    coffee:
      options:
        # Don't wrap files in CommonJS module wrapper
        bare: true
        # Create source maps for debugging
        sourceMap: true
      # our application's source files;
      app:
        files: expandedMapping(config.app.root, config.app.glob, config.tmpDir)
      # the test source:
      tests:
        files: expandedMapping(config.tests.root, config.tests.glob, config.tmpDir+"/tests")

    # compile app/assets/javascripts/templates/**/*.ejs into .mocha/templates.js
    jst:
      compile:
        options:
          processName: templatePathFor
        files:
          ".mocha/templates.js": "#{config.templates.root}/#{config.templates.glob}"

    # lets us directly open the browser to the spec runner:
    open:
      tests:
        url: "http://#{config.server.hostname}:#{config.server.port}/#{config.specRunner}"

    watch:
      # Reload the Gruntfile, if changed
      grunt:
        files: ["Gruntfile.coffee"]
        tasks: []
      # when the application source changes, we re-lint it, clean, recompile,
      # and rebuild the spec runner
      app:
        files: "#{config.app.root}/#{config.app.glob}"
        tasks: ["coffeelint:app", "clean:app", "coffee:app", "specrunner"]
      # when tests change, we lint them, clean, recompile, and rebuild the
      # specrunner.
      tests:
        files: "#{config.tests.root}/#{config.tests.glob}"
        tasks: ["coffeelint:tests", "clean:tests", "coffee:tests", "specrunner"]
      # when templates change, we rebuild them and the spec runner
      templates:
        files: "#{config.templates.root}/#{config.templates.glob}"
        tasks: ["clean:templates", "jst", "specrunner"]
      # when the specrunner changes, we re-run the test suite
      specrunner:
        options:
          spawn: false
        files: [config.specRunner]
        tasks: ["rerun"]

    # configuration for test server
    # using the server mitigates caching issues when running in browser
    connect:
      server:
        options: config.server

    # Tells mocha-phantomjs where to find the specrunner
    mocha_phantomjs:
      all:
        options: 
          urls:["http://#{config.server.hostname}:#{config.server.port}/#{config.specRunner}"]

  # load grunt plugins:
  grunt.loadNpmTasks "grunt-contrib-clean"
  grunt.loadNpmTasks "grunt-coffeelint"
  grunt.loadNpmTasks "grunt-contrib-coffee"
  grunt.loadNpmTasks "grunt-contrib-jst"
  grunt.loadNpmTasks "grunt-contrib-connect"
  grunt.loadNpmTasks "grunt-contrib-watch"
  grunt.loadNpmTasks "grunt-open"
  grunt.loadNpmTasks "grunt-mocha-phantomjs"

  # builds the spec runner from a template
  grunt.registerTask "specrunner", "set up spec runner", ->
    context = _.merge({}, config.mocha, {
      tests: testModuleNames(), config: config
    })
    output = _.template(config.specRunnerTemplate, context)
    grunt.file.write(config.specRunner, output)
    grunt.log.writeln("File #{config.specRunner} created.")

  # If using the command line, we re-run the tests;
  # if using the browser, we trigger a reload.
  grunt.registerTask "rerun", "Re-runs the tests", ->
    if config.runningIn is "console"
      grunt.log.writeln "Re-running tests in console."
      grunt.task.run(["mocha_phantomjs"])
    else
      grunt.log.writeln "Re-running tests in browser."
      liveReloadServer.changed body: files: [config.specRunner]

  # the "running" and "serving" tasks keep track of where the tests are being
  # run; this is used by the "rerun" task to determine whether to re-run the
  # tests on the command line or to trigger a reload in the browser.
  grunt.registerTask "running", "tests are being run in the console", ->
    config.runningIn = "console"

  # we also set up the live-reload server here.
  # grunt-contrib-watch has a livereload option, but it doesn't seem to trigger
  # live reloading correctly
  grunt.registerTask "serving", "tests are being run in the browser", ->
    config.runningIn = "browser"
    liveReloadServer = require("tiny-lr")()
    liveReloadServer.listen 35729, (err) ->
      if err
        grunt.log.writeln err.message
      else
        grunt.log.writeln("LiveReload Server Started")

  # test:build just builds the test suite in .mocha; it's required by all the
  # test-running tasks
  grunt.registerTask "test:build", [
    "clean"
    "jst"
    "coffeelint"
    "coffee"
    "specrunner"
  ]

  # create tasks for one-off runs of the tests, either in-browser or on the
  # command line
  grunt.registerTask "test:run", [
    "test:build"
    "connect"
    "mocha_phantomjs"
  ]
  grunt.registerTask "test:serve", [
    "test:build"
    "connect:server:keepalive"
    "open"
  ]

  # create watcher tasks for server and command line
  grunt.registerTask "test:run:watch", [
    "running"
    "test:build"
    "connect"
    "mocha_phantomjs"
    "watch"
  ]
  grunt.registerTask "test:serve:watch", [
    "serving"
    "test:build"
    "connect"
    "open"
    "watch"
  ]

  # 'test' is just an alias for test:run; we use this in our CI environment.
  grunt.registerTask "test", ["test:run"]


