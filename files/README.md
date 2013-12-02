# My Project #

### Frontend Tests

#### Setup

To get set up for frontend testing, just install the frontend tools w/ npm: 

```bash
cd myproject
npm install --save-dev
```

#### Testing

* `grunt test:run` to run tests on the command line
* `grunt test:serve` will serve tests at `http://localhost:8000/.mocha/index.html`

If you want to automatically re-run test when files are saved use:

* `grunt test:run:watch` to automatically run tests on the command line
* `grunt test:serve:watch` to automatically run tests in the browser.  Note: you will need a LiveReload extension for your browser.

### CI

We use circleci.com. Currently at
[http://circleci.com/username/project](http://circleci.com/username/project)

## Deploying

for dev and staging, we use circle ci git based deploy. pushing changes to the
`develop` or `staging` branch will make circleci run tests and if they pass, the
branch will be pushed to its respective server.

