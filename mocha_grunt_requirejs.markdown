Testing your Play/CoffeeScript App with Grunt, Mocha, RequireJS and friends
===========================================================================

I recently worked on a Scala/Play2.1 project that made heavy use of Spine.js for
the frontend.  When I came onboard, the frontend looked like this:

  * tests used [Jasmine][jasmine]; run via [jasmine-headless-webkit][jhw]
  * there was no module system&emdash;objects in the sytem were simply stored
    in a namespace object
  * code was all native JS
  * Assets were being compiled by [Satchel][satchel]

Our goal was to move to CoffeeScript, use Play's [built-in
support][playrequire] for [RequireJS][requirejs], and use [Mocha][mocha] for the
frontend unit and functional tests.

## Why Coffee/RequireJS/Mocha? ###

### CoffeeScript ###

I chose CoffeeScript because it provides an easy, lightweight syntax, and
abstracts a lot of common scripting boilerplate.  This allows me to focus on the
logic, rather than the details of things like `for` loops and `null` checks.
Short answer: CoffeeScript writes more consistent JavaScript than I do.

### RequireJS ###

I feel that on any project of reasonable size, a module system is a must-have;
by the time I got to this project, it had already started to outgrow its
namespacing.  I used to think namespacing was an acceptable way to manage
JavaScript modules; I no longer think so for one reason: dependency management.

Dependencies should be clearly defined, and should not present any hassle to the
developer.  They should be managed by the module system itself, and circular
depencies should cause the program to throw an explicit error, as they are an
indication of tight coupling.

That said, RequireJS was an obvious choice on this project, because Play 2.1.x
supports it out of the box, and uses it as the primary means of serving assets.
Switching to RequireJS allowed us to kill two birds with one stone: we got a
module system and a build tool in one.

### Mocha ###

I decided to use Mocha for three reasons:

**Jasmine/JHW don't work well with the CoffeeScript/RequireJS combo.**

Jasmine-Headless-Webkit has, at best, poor support for the
CoffeeScript/RequireJS combo; JHW compiles all CoffeeScript files with the
`.coffee.js` extension, which causes the default module path to be something
like `lib/MyLib.coffee` instead of `lib/MyLib`.  Since Play was configured to
build the modules with a `.js` extension, modules were referenced in the
application code as like `lib/MyLib`.  I've seen several Jasmine/CoffeeScript
solutions that use the CoffeeScript plugin for RequireJS; that would work fine,
except that Play's build system doesn't use it for compiling CoffeeScript, so
our modules don't use the `cs!` prefix to load their dependencies.

Additionally, Jasmine really doesn't play well with asynchrounosly-loaded
scripts. While Jasmine can be [shoehorned into running asyncrounous
specs][jasmine-async-describe], it doesn't work well; i got our specs running on
the command line, but the in-browser version never worked correctly.

Moreover, jasmine's command-line runner provided uselessly terse output; errors
and test failures did not include a stack trace or any contextual information.

**Mocha is flexible.**

Mocha really does support asynchronous loading, and has support for running
individual tests asynchronously as well, via its `done` callback.

Mocha supports [multiple test interfaces][mocha-interfaces]: BDD style
(describe, context, it&mdash;my preference), TDD style (suite, test), Exports
(returns a hash of tests), and QUnit style (flattened). It also supports a
[variety of assertion libraries][mocha-assertions]; I'm using [chai][chai], but
Mocha is known to work with [should.js][shouldjs], [expect.js][expectjs], and
[better-assert][better-assert] as well.

**Mocha's reporters are great.**

Whether in the browser or on the command line, Mocha has great reporters.

In the browser, Mocha tells you how many tests pass, fail, and the total, as
well as a progress indicator.  The reporter is also fairly nice-looking, for a
test suite.  You can show/hide failed tests and passed tests.

Running on the command line, mocha provides a variety of runners, each adjusted
for different needs; if you're watching for changes, using the "min" reporter is
really nice, as it only tells you about failures.  The "spec" reporter is also
nice: it lists each description in a tree, and gives the run time for slow
tests, as well as failures with a backtrace.  Oh, and of course, don't miss the
["Nyan"][nyan-mocha] reporter.

## Configuring Play for RequireJS ##

i first changed the play configuration to use requirejs for packaging assets:

```scala
val main = play.project(appname, appversion, appdependencies)
    .settings( requirejs += "app.js" )
```

and then wrapped each of the .js files in a `define` block:

```javascript
define(['lib/somelib'], function(somelib){
  // somelib is a dependency ----^
  // code goes here...
})
```

and then changed all the namespace references to use modules.  For example, the
`UserProfileController` relied on the `User` model as `App.Models.User`; this
was changed to `User` and the define block for `UserProfileController` was
changed to look like this:

```javascript
define(['models/User], function(User){
  var UserProfileController = Spine.Controller.sub();
  // other code ...
  return UserProfileController;
});
```

## Converting to CoffeeScript ##

The next step was to convert the JavaScript source to CoffeeScript, which I did
w/ the [js2coffee][js2coffee] utility and a little bash:

```bash
for file in app/assets/javascripts{,/**}/*.coffee
do
  js2coffee $file > "${file%%.coffee}.js"
  rm $file
done
```

I then manually converted some code into CoffeeScript classes, where it made
sense. For example:

```coffee
User = Spine.Model.sub({
  isAdmin: () ->
    @role is 'admin';
},{
  admins: () ->
    @select (user) ->
      user.isAdmin()
})
```

would be changed to

```coffee
define ['spine'], (Spine) ->

  class User extends Spine.Model
    @admins: -> @select (user) -> user.isAdmin()
    isAdmin: -> @role is 'admin'
```

## Setting up Mocha ##

I saw several guides to using Mocha with RequireJS; none of them seemed to
actually run the tests. I finally landed on using [Grunt][grunt] to do the
following:

- build application templates
- lint all the coffeescript
- compile the application source
- compile the tests
- build an HTML spec runner
- Run tests on the command line, via PhantomJS
- **Or** start a webserver, and open the runner in the browser
- Watch for changes and recompile

### Grunt Setup ###

To install Grunt and some related tools, I set up this `package.json` file:

```json
{
  "name": "my-application",
  "version": "0.0.0",
  "repository": "git@github.com:usernaem/repository.git",
  "dependencies": {
    "requirejs": "2.1.x",
    "sinon": "1.6.x",
    "chai": "1.6.x",
    "mocha": "1.9.x",
    "sinon-chai": "2.4.x",
    "chai-jquery": "1.1.x",
    "chai-things": "0.2.x"
  },
  "devDependencies": {
    "grunt": "0.4.x",
    "grunt-cli": "0.1.x",
    "grunt-open": "0.2.x",
    "grunt-coffeelint": "0.x.x",
    "grunt-mocha": "0.3.x",
    "grunt-mocha-phantomjs": "0.3.x",
    "grunt-contrib-connect": "0.5.x",
    "grunt-contrib-jst": "0.5.x",
    "grunt-contrib-coffee": "0.7.x",
    "grunt-contrib-clean": "0.5.x",
    "grunt-contrib-watch": "0.5.x",
    "tiny-lr": "0.0.x"
  }
}
```

Our Node-based tools can now be installed w/ `npm install --save`

Now we need to create `Gruntfile.coffee`; Grunt uses the CommonJS module
pattern, so we start our file off with

```coffee
module.exports = (grunt) ->
```

I put some configuration vars at the top; copying the values all over the place
is a pain.

```coffee
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
```

Grab [LoDash][lodash] real quick

```coffee
_ = grunt.util._
```

Next, we need a few helper methods

```coffee
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
```

Let's add some configuration for compiling our CoffeeScript source and tests

```coffee
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
```

And some configuration for compiling our JST templates

```coffee
# compile app/assets/javascripts/templates/**/*.ejs into .mocha/templates.js
jst:
  compile:
    options:
      processName: templatePathFor
    files:
      ".mocha/templates.js": "#{config.templates.root}/#{config.templates.glob}"
```

Add a config to serve our files

```coffee
# configuration for test server
# using the server mitigates caching issues when running in browser
connect:
  server:
    options: config.server
```

Load the tasks for our Grunt plugins:

```coffee
# load grunt plugins:
grunt.loadNpmTasks "grunt-mocha-phantomjs"
grunt.loadNpmTasks "grunt-contrib-jst"
grunt.loadNpmTasks "grunt-contrib-coffee"
grunt.loadNpmTasks "grunt-contrib-clean"
grunt.loadNpmTasks "grunt-contrib-connect"
```

Add a task for creating our spec runner

```coffee
# builds the spec runner from a template
grunt.registerTask "specrunner", "set up spec runner", ->
  context = _.merge({}, config.mocha, {
    tests: testModuleNames(), config: config
  })
  output = _.template(config.specRunnerTemplate, context)
  grunt.file.write(config.specRunner, output)
  grunt.log.writeln("File #{config.specRunner} created.")
```

As mentioned in the task, we'll need the spec runner template

```coffee
<!DOCTYPE>
<html>
<head>
  <meta charset="utf-8">
  <% _.each(static_deps, function(dependency){ %>
  <script type="text/javascript" src="../<%= dependency %>"></script>
  <% }) %>
  <script type="text/javascript" src="./templates.js"></script>
  <!-- 
    Directly include config file to avoid nested requires
    each time a resource is required (1 to get the paths
    and a second time to actually require the desired file).
  -->
  <script type="text/javascript">
    mocha.setup('bdd');
    var expect = chai.expect;
  </script>
  <link rel="stylesheet" href="../node_modules/mocha/mocha.css"></script>
</head>
</html>
<body>
  <div id="mocha"></div>
  <!-- Include the tests. -->
  <script type="text/javascript" charset="utf-8">
    require([<%= _.map(tests, function(test){ return '"'+test+'"'} ).join(', ') %> ], function(){

      if(window.mochaPhantomJS) {
        mochaPhantomJS.run()
      } else {
        mocha.run();
      }

    });
  </script>
  <% if(config.runningIn === "browser") { %>
  <script src="//localhost:35729/livereload.js" type="text/javascript"></script>
  <% } %>

</body>
</html>
```

and the `mocha.yml` file

```coffee
static_deps:
  - public/javascripts/jquery-1.10.1.min.js
  - public/javascripts/lodash.min.js
  - public/javascripts/moment.min.js
  - public/javascripts/store.min.js
  - public/javascripts/spine.js
  - public/javascripts/spine/ajax.js
  - public/javascripts/spine/local.js
  - public/javascripts/spine/route.js
  - node_modules/sinon/pkg/sinon.js
  - node_modules/chai/chai.js
  - node_modules/sinon-chai/lib/sinon-chai.js
  - node_modules/chai-jquery/chai-jquery.js
  - node_modules/chai-things/lib/chai-things.js
  - node_modules/mocha/mocha.js
  - node_modules/requirejs/require.js
  - test/javascripts/support/mocket.io.js
  - test/javascripts/support/stub-persistence.js
  - test/javascripts/support/jquery-stubs.js
  - test/javascripts/support/session.js
```

Add the config for mocha-phantomjs

```coffee
# Tells mocha-phantomjs where to find the specrunner
mocha_phantomjs:
  all:
    options: 
      urls:["http://#{config.server.hostname}:#{config.server.port}/#{config.specRunner}"]
```

Almost forgot to add a `clean` task config

```coffee
clean: 
  app: [
    "#{config.tmpDir}/**/*",
    "!#{config.tmpDir}/tests",        # ignore tests
    "!#{config.tmpDir}/tests/**",     #        test files
    "!#{config.tmpDir}/templates.js"  #        and templates
  ]
  tests: [config.specRunner, "#{config.tmpDir}/tests"]
  templates: ["#{config.tmpDir}/templates.js"]
```

And finally, add tasks for running the whole thing

```coffee
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

# 'test' is just an alias for test:run; we use this in our CI environment.
grunt.registerTask "test", ["test:run"]
```

Wow, that was a lot of setup! At this point, our `Gruntfile.coffee` should look
like this:

```coffee
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

    # compile app/assets/javascripts/templates/**/*.ejs into .mocha/templates.js
    jst:
      compile:
        options:
          processName: templatePathFor
        files:
          ".mocha/templates.js": "#{config.templates.root}/#{config.templates.glob}"

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

    clean: 
      app: [
        "#{config.tmpDir}/**/*",
        "!#{config.tmpDir}/tests",        # ignore tests
        "!#{config.tmpDir}/tests/**",     #        test files
        "!#{config.tmpDir}/templates.js"  #        and templates
      ]
      tests: [config.specRunner, "#{config.tmpDir}/tests"]
      templates: ["#{config.tmpDir}/templates.js"]

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
  grunt.loadNpmTasks "grunt-mocha-phantomjs"
  grunt.loadNpmTasks "grunt-contrib-jst"
  grunt.loadNpmTasks "grunt-contrib-coffee"
  grunt.loadNpmTasks "grunt-contrib-clean"
  grunt.loadNpmTasks "grunt-contrib-connect"
  grunt.loadNpmTasks "grunt-contrib-watch"
  grunt.loadNpmTasks "grunt-open"
  grunt.loadNpmTasks "grunt-coffeelint"

  # builds the spec runner from a template
  grunt.registerTask "specrunner", "set up spec runner", ->
    context = _.merge({}, config.mocha, {
      tests: testModuleNames(), config: config
    })
    output = _.template(config.specRunnerTemplate, context)
    grunt.file.write(config.specRunner, output)
    grunt.log.writeln("File #{config.specRunner} created.")

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

  # 'test' is just an alias for test:run; we use this in our CI environment.
  grunt.registerTask "test", ["test:run"]
```

and we should be able to run the whole thing with `grunt test`.

### Jasmine to Chai Converstion ###

Next I had to change all the tests to use the [Chai DSL][chaijs] instead of Jasmine's
expectations.  I decided to use Chai's [expect API][chaiexpect], since it's the
closes to Jasmine's, and entails the least amount of work.

Note, there are other advantages to using the expect API&mdash;namely, the
should API (`foo.should.equal('bar')`) polutes all objects, conflicts with
objects that have a `should` property, and doesn't work on `null` or
`undefined`.  Using `expect(foo).to.equal('bar')` is more consistent, and
doesn't require us to inject anything into `Object`.

I don't know of any super quick method to do this; I pulled up
[TextMate][textmate] to use its project-wide find/replace, and kept re-running
the tests in my browser until I had them all passing again.  Most of the work
was just making sure I was using the right DSL methods.  I switched from using
[jasmine-jquery][jasmine-jquery] and [jasmine-sinon][jasmine-sinon] to using
[chai-jquery][chai-jquery] and [sinon-chai][sinon-chai]; there are a number of
small differences between them, for example:

* `toContainHtml` doesn't exactly correspond to `to.contain.html`, nor does
  `toContainText` to `to.contain.text`
    - the HTML methods listed above seem to use different procedures for
      comparing HTML; I had to normalize the output I was checking for
* While Jasmine uses methods almost exclusively, Chai and its plugins tend to
  favor JavaScript property getters whenever possible.  This can lead to some
  confusing behavior.

## Making It Easier ###

So, the test suite is converted, and the tests are passing. Great! Though,
constantly recompiling and refreshing the browser sure was a pain.  What if
there was some way to fix that?

**Watch to the rescue!**

Adding Watch tasks can make life a breeze&mdash;we'll just have it monitor for
changes and recompile/refresh all by itself.  [Laziness][threevirtues] restored.

We want to watch for a few things:

- `Gruntfile.coffee`
- application code in `app/assets/javascripts`
- templates in `app/assets/templates`
- tests in `test/javascripts`
- the spec runner

The idea is this&mdash;when changes happen in the application code, templates,
or tests, we will clean and recompile the changed assets; we will then rebuild
the specrunner, which will trigger our watch task, re-running the tests.

Since I am a [lazy][threevirtues] programmer, I don't want to be bothered with
remembering the URL to the test server and typing it into my browser, so I'm
going to add the [grunt-open][grunt-open] plugin and configure it to do so.

```coffee
# lets us directly open the browser to the spec runner:
open:
  tests:
    url: "http://#{config.server.hostname}:#{config.server.port}/#{config.specRunner}"
```

Load the `open` task with

```coffee
grunt.loadNpmTasks "grunt-open"
```

I also don't want to be bothered with manually checking my code style (or that
of others).  If only there was a tool for that...
([grunt-coffeelint][grunt-coffeelint])

```coffee
coffeelint:
  options:
    no_trailing_whitespace: {level: 'error'}
    no_throwing_strings: {level: 'ignore'}
    max_line_length: {level: 'warn'}
  app: [config.app.root, config.app.glob].join('/')
  tests: [config.tests.root, config.tests.glob].join('/')
```

And load the `coffeelint` task with

```coffee
grunt.loadNpmTasks "grunt-coffeelint"
```

Let's add some tasks to run when file changes happen.

```coffee
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
```

The `serving` and `running` tasks are responsible for setting an environment
variable that the `rerun` task looks for. `serving` also starts our
[LiveReload][livereload] server.

Our `rerun` task simply re-runs the tests if we are running them on the command
line, or in the case of browser-based tests, triggers a reload.

```coffee
# If using the command line, we re-run the tests;
# if using the browser, we trigger a reload.
grunt.registerTask "rerun", "Re-runs the tests", ->
  if config.runningIn is "console"
    grunt.log.writeln "Re-running tests in console."
    grunt.task.run(["mocha_phantomjs"])
  else
    grunt.log.writeln "Re-running tests in browser."
    liveReloadServer.changed body: files: [config.specRunner]
```

Now we can configure watch.  Here's our config:

```coffee
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
```

We also need to load the watch task

```coffee
  grunt.loadNpmTasks "grunt-contrib-watch"
```

And we need some tasks to tie our watch-foo together

```coffee
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
```

`Gruntfile.coffee` should now look like this:

```coffee
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


```

and you can run your tests in watch mode via `grunt test:run:watch`
(command-line) or `grunt test:serve:watch` (browser).

## CircleCI Setup ##

I had to make a couple of quick changes to our `circle.yml` file to get the
mocha tests running:

```yml
test:
  override:
    - grunt test:run
dependencies:
  override:
    - npm install --save-dev
```

## Documentation ##

Whenever you make a change this big, it's always a good idea to update your
`README`; I simply added this:

```markdown
### Frontend Tests

#### Setup

To get set up for frontend testing, just install the frontend tools w/ npm: 

    cd servicetown
    npm install --save-dev

#### Testing

* `grunt test:run` to run tests on the command line
* `grunt test:serve` will serve tests at `http://localhost:8000/.mocha/index.html`

If you want to automatically re-run test when files are saved use:

* `grunt test:run:watch` to automatically run tests on the command line
* `grunt test:serve:watch` to automatically run tests in the browser.  Note: you will need a LiveReload extension for your browser.
```

## Wrapping Up ##

Well, I started with a broken, half-baked Jasmine setup (not that Jasmine's a
bad tool); now I have a beautiful Mocha-based setup with linting, automatic
re-runs, and a nice way to open the tests in-browser.

### Improvements ###

This setup works nicely, but could be improved:

* Only recompile/delete specific files when their source is changed, rather than
  clean and recompile the whole shebang.
* Move configuration to an external file
* You may have noticed that I don't use RequireJS for all the external
  dependencies; this could be fixed via RequireJS' `shim` option.
* Export custom tasks to their own library
* Load grunt tasks via [load-grunt-tasks][load-grunt-tasks] or similar.


[jasmine]:http://pivotal.github.io/jasmine/
[jhw]:http://johnbintz.github.io/jasmine-headless-webkit/
[satchel]:https://github.com/dansimpson/satchel
[requirejs]:http://requirejs.org/
[playrequire]:http://www.playframework.com/documentation/2.1.x/RequireJS-support
[js2coffee]:https://github.com/rstacruz/js2coffee
[nyan-mocha]:http://tjholowaychuk.com/post/25314967097/mocha-1-2-0-now-with-more-nyan
[grunt]:http://gruntjs.com/
[mocha]:http://visionmedia.github.io/mocha/
[mocha-interfaces]:http://visionmedia.github.io/mocha/#interfaces
[jasmine-async-describe]:https://engineering.groupon.com/2012/javascript/testing-javascript-with-jasmine-and-requirejs/
[mocha-assertions]:http://visionmedia.github.io/mocha/#assertions
[chai]:http://chaijs.com/
[shouldjs]:https://github.com/visionmedia/should.js
[expectjs]:https://github.com/LearnBoost/expect.js
[better-assert]:https://github.com/visionmedia/better-assert
[lodash]:http://lodash.com/
[chaiexpect]:http://chaijs.com/api/bdd/
[textmate]:http://macromates.com/
[jasmine-jquery]:https://github.com/velesin/jasmine-jquery
[jasmine-sinon]:https://github.com/froots/jasmine-sinon
[chai-jquery]:https://github.com/chaijs/chai-jquery
[sinon-chai]:https://github.com/domenic/sinon-chai
[threevirtues]:http://threevirtues.com/
[grunt-open]:https://github.com/jsoverson/grunt-open
[grunt-coffeelint]:https://github.com/vojtajina/grunt-coffeelint
[load-grunt-tasks]:https://github.com/sindresorhus/load-grunt-tasks

