pavarotti - easily create CRUD controllers
==========================================

We consistently require controllers that have CRUD functionality (create, read,
update and delete).

To avoid institutionalising ourselves, we define generic
versions of these methods here which we can then use to e.g. build a
controller that manages users. Such a controller would be created with
`usersController = require('pavarotti').methodsFor(User)`, where `User` is the
user model.

### Methods

The methods we would like to build abstract versions of, are:

* **set**

  Create an item with the given params, or update the item with given `id` with
  the given params. The newly saved item is returned.

* **get**

  Get a single item by its id.

* **find**

  Get all items that match the criteria given, possibly paging and sorting the
  result.

* **remove**

  Delete a single item by its id.

### Config

We can customise these methods by passing in configuration options to the main
`methodsFor` method, which constructs the CRUD controller. The options are:

#### set

* **beforeSet** `: Model |-> Model`

  bfunction called before the model is saved to the database. Is given the model
  that will be saved. The result is the final object saved to the database. An
  error stops the method.

  Defaults to `bf.identity`.

* **afterSet** `: Model |-> Model`

  bfunction called after the model has been saved to the database. Is given the
  model that was saved. The result will be the output of the `set` method. An
  error stops the method.

  Defaults to `bf.identity`.

#### get

* **afterGet**: `: Model |-> Model`

  bfunction called after the model has been retrieved from the database. Is
  given the model that was retrieved. The result will be the output of the
  `get` method. An error stops the method.

  Defaults to `bf.identity`.

#### find

* **beforeFind**: `: Params |-> Params`

  bfunction called at the beginning of the `find` method. Is given the params to
  the `find` method. The result will be fed into the next stem of the `find`
  method. An error stops the method.

  Defaults to `bf.identity`.

* **buildFindFilter** `: Params |-> FindFilter`

  bfunction that, given the params to the `find` method, builds the object that
  is given to mongoose to filter the model collection (the `find()` filter). If
  null, builds the find filter using properties that are in the `filter` object
  in the params.

  Defaults to `null`.

* **buildFindSort** `: Params |-> FindSort`

  bfunction that, given the params to the `find` method, builds the object that
  is given to mongoose to sort the model collection (the `sort()` object). If
  null, builds the sort filter using properties thare are in the `sort` object
  in the params such that e.g. `{ sort: { name: 'asc' } }` becomes
  `{ name: 1 }`.

  Defaults to `null`.

* **afterFind**: `: { items: Model[], total: number, filteredTotal: number } |-> any

  bfunction that, given the final result of the `find` method (results, number
  of total items and number of filtered items) returns some object that will be
  the output of the `find` method.

  Defaults to `bf.identity`.

Dependencies
------------

    _           = require 'underscore'
    bf          = require 'barefoot'

Abstraction
-----------

The CRUD controller methods are generated once from a single initialisation call
to `methodsFor`. This method takes the model that the CRUD methods are for and a
variety of additional configuration methods that lets the consumer of this CRUD
controller customise each of the CRUD methods.

    methodsFor = (model, config = {}) ->

      config = _.defaults config,
        beforeSet: bf.identity
        afterSet: bf.identity

        afterGet: bf.identity

        beforeFind: bf.identity
        buildFindFilter: null
        buildFindSort: null
        afterFind: bf.identity

      crud = {}

Create and update (set)
-----------------------

We create and update with the single `set` method. This performs an insert
operation if no `id` is given, and an update operation is an `id` is given. In
any case, the newly saved item is returned.

      crud.set =

        bf.chain -> [
          bf.validate
            _id: String

          getOrCreate
          config.beforeSet
          save
          config.afterSet
        ]

First, attempt to retrieve the item by its id. If there is none found then
create a new item. We use mongoose's `set` method to apply the given params to
the fetched model.

      getOrCreate = (params, done) ->

        w = bf.errorWrapper done

        model.findById params.id, w (item) ->

          item ?= new model()
          item.set params

          done null, item

Now, we have a fully populated offer model. All that's left to do is save it!

      save = (item, done) ->
        item.save done

Read (get)
----------

We can retrieve a single item by its id very simply. This method takes one
param, `id`, and returns the item (or null if none exists).

      crud.get =

        bf.chain -> [
          bf.validate
            id: String

          bf.select (p) -> p.id
          _.bind model.findById, model
          config.afterGet
        ]

Read (find)
-----------

We can search for items using a single super method that takes many different
filtering params (`findFilterParams`) and sorting params (`findSortParams`) and
retrieves a paginated list of items that match. The consumer of the CRUD API
helper is able to modify the mongo `find()` object and `sort()` object.

      crud.find =

        bf.chain -> [
          bf.validate
            _filter: Object
            _sort: Object
            _skip: Number
            _limit: Number

          config.beforeFind
          bf.parallel [
            config.buildFindFilter ? buildFilter
            config.buildFindSort ? buildSort
            bf.identity
          ]
          runQuery
          config.afterFind
        ]

The default `buildFindFilter` just filters on the parameters given in
`params.filter`.

      buildFilter = (params, done) ->

        done null, params.filter

The default `buildFindSort` convers the `params.sort` object given from e.g.
`{prop: 'asc'}` to `{prop: 1}`.

      buildSort = (params, done) ->

        sort = null

        if params.sort?
          sort = {}
          for p, o of params.sort
            if o == 'asc'
              sort[p] = 1
            else if o == 'desc'
              sort[p] = -1

        done null, sort

We require very flexible pagination, so running the query is a little tedious,
though simple enough.

      runQuery = ([filter, sort, params], done) ->

        seq = bf.sequence done

        filter ?= {}
        sort ?= {}

        total = 0
        filteredTotal = 0

        seq.then (next) ->
          model.find().count seq.w (count) ->
            total = count
            next()

        seq.then (next) ->
          model.find(filter).count seq.w (count) ->
            filteredTotal = count
            next()

        seq.then (next) ->
          query = model.find(filter)

          if params.skip?
            query = query.skip(params.skip)
          if params.limit?
            query = query.limit(params.limit)

          query.exec seq.w (items) ->
            done null,
              items: items
              total: total
              filteredTotal: filteredTotal

Delete (remove)
---------------

Deleting or removing an item is a simple method that retrieves an object by its
`id` and then removes it if it exists. If no item with the given `id` exists,
nothing happens.

      crud.remove =

        bf.chain -> [
          bf.validate
            id: String

          _.bind model.remove, model
        ]

Finishing up
------------

We must conclude the `methodsFor` function we began to define.

      return crud

And then export this function.

    module.exports = {
      methodsFor
    }
