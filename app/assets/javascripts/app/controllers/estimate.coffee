
angular.module('Constructor').controller 'EstimateController', class EstimateController
  @$inject: ['$scope', '$http', '$filter', 'pHelper', 'toaster']

  constructor: (@scope, @http, @filter, @pHelper, @toaster) ->
    @scope.ctrl     = @
    @scope.estimate = @pHelper.get('estimate')
    @scope.expense  = @pHelper.get('expense')
    @scope.stages   = @pHelper.get('stages')
    @scope.discount = @pHelper.get('discount')
    @scope.products = @pHelper.get('products')
    @scope.accept   = 'false'

    if @pHelper.get('export_pdf')
      window.open($('#export_pdf_button').attr('href'), '_blank')

    this.initModals()
    this.parseEstimate()
    this.parseProducts()
    this.parseExpense()
    this.parseDiscount()
    this.parseStages()
    for i in [1..3]
      this.recalcStage(i)
    this.saveJsonValue()

    toaster = @toaster
    $('input[type=number]').on('change', (e) ->
      value  = $(this).val()
      regexp = new RegExp(/^\d+[\.,]*\d{0,4}$/)
      if parseFloat(value) <= 0 || regexp.exec(value) == null
        toaster.error('Указано неверное значение')-41
    )
    $('#floors').collapse('show') if @scope.estimate.second_floor


  validate: (ex = false)->
    custom   = @scope.custom
    stages   = @scope.stages
    estimate = @scope.estimate
    event.preventDefault()

    validate = { error: false, message: null }

    if stages[0].products.length <= 0 && stages[1].products.length <= 0 && stages[2].products.length <= 0
      validate = { error: true, message: 'Необходимо указать хотя бы один сметный продукт' }

    angular.forEach stages, (stage,k) ->
      angular.forEach stage.products, (product,l) ->
        if product.custom
          angular.forEach product.sets, (set,m) ->
            at_least_one_present = false
            angular.forEach set.items, (item,n) ->
              item.quantity == 0 if item.quantity == null
              at_least_one_present = item.quantity > 0 unless at_least_one_present
              if item.quantity < 0 && !validate.error
                validate = { error: true, message: 'Неверно указано количество составляющей сметного продукта' }

            validate = { error: true, message: 'Неверно указано количество составляющей сметного продукта' } unless at_least_one_present
        else
          if product.quantity <= 0 && !validate.error
            validate = { error: true, message: 'Неверно указано количество сметного продукта' }

    if estimate.second_floor
      second_floor = {
        min: parseFloat($('#estimate_second_floor_height_min').val()),
        max: parseFloat($('#estimate_second_floor_height_max').val())
      }
      third_floor = {
        min: parseFloat($('#estimate_third_floor_height_min').val()),
        max: parseFloat($('#estimate_third_floor_height_max').val())
      }
      if second_floor.max < second_floor.min
        validate = { error: true, message: 'Неверно указана высота второго этажа' }
      if third_floor.max < third_floor.min
        validate = { error: true, message: 'Неверно указана высота третьего этажа' }

    if validate.error
      @toaster.error(validate.message)
    else
      if ex
        $('#export').val(1)
      $('form').submit()
    true

  showAddModal: (stage) ->
    @scope.addModal.header       = 'Добавление сметного продукта. Этап ' + stage
    @scope.addModal.products     = this.getProducts(stage)
    @scope.selectedProduct       = null
    @scope.selectedProductId     = 'Выберите сметный продукт'
    @scope.selectedProductCustom = false
    @scope.selectedSetId         = 'Выберите сборку'
    @scope.selectedSet           = null
    @scope.currentStage          = stage

    $('#productHint').collapse('hide')
    $('#add-product').modal('show')
    true

  showEditModal: (stage, product) ->
    product = this.getProductFromStage(product)

    @scope.currentStage              = stage
    @scope.editModal.header          = 'Редактирование сметного продукта. Этап ' + stage
    @scope.selectedEditProduct       = product
    @scope.selectedEditProductId     = product.name
    @scope.selectedEditProductCustom = product.custom

    if product.custom
      set = product.sets.find((x) -> x.selected == true)
      @scope.selectedEditSetId         = set.id
      @scope.selectedEditSet           = set

    $('#productEditHint').collapse('hide')
    $('#edit-product').modal('show')
    true

  acceptSolution: () ->
    @scope.accept = 'true'
    $('form').submit()
    true

  addProduct: () ->
    debugger
    estimate     = @scope.estimate
    discount     = @scope.discount
    stage_number = @scope.currentStage
    product      = @scope.selectedProduct
    quantity     = $('#product-quantity').val()
    error        = false
    message      = 'Необходимо выбрать сметный продукт'

    regexp = new RegExp(/^\d+[\.,]*\d{0,4}$/)

    product_in_stage = this.getProductFromStage(product.id)
    return @toaster.error('Сметный продукт "' + product.name + '" уже добавлен') if product_in_stage

    stage = this.getStage(stage_number)
    if product.custom

      product.price_with_work    = 0
      product.price_without_work = 0

      set_id = @scope.selectedSetId
      if set_id == "Выберите сборку"
        error = true
        message = 'Необходимо выбрать сборку сметного продукта'

      set = product.sets.find((x) -> x.id == parseInt(set_id))
      at_least_one_present = false

      item_quantites = []

      $.each($('.template-quantity'), (i, v) ->
        quantity     = parseFloat($(v).val())
        at_least_one_present = quantity > 0 unless at_least_one_present

        set.selected = true
        set.items[i] = Object.assign(set.items[i], {quantity: quantity})

        if $(v).val() == '' && error == false
          error = true
          message = 'Необходимо указать количество для всех составляющих сметного продукта'

        item_quantites.push(quantity)
        product.price_with_work += set.items[i].value.price * quantity
        unless set.items[i].value.work_primitive
          product.price_without_work += set.items[i].value.price * quantity
      )

      $.each(product.sets, (i, s) ->
        if !s.selected
          $.each(s.items, (j, item) ->
            item.quantity = item_quantites[j]
          )
      )

      unless at_least_one_present
        error = true
        message = 'Неверно указано количество'

      product = Object.assign(product, {quantity: 1, with_work: true})
    else
      if quantity == ''
        error   = true
        message = 'Необходимо указать количество сметного продукта'

      if (parseFloat(quantity) <= 0 || regexp.exec(quantity) == null) && error == false
        error   = true
        message = 'Неверно указано количество'

      product = Object.assign(product, {quantity: parseFloat(quantity), with_work: true})

    unless error
      this.recalcProductPrice(stage, product)
      stage.products.push(product)

      this.recalcStage(stage.number)

      $('#product-quantity').val(null)
      $('#add-product').modal('hide')
      true
    else
      @toaster.error(message)

  deleteProduct: (stage, id) ->
    debugger
    product = stage.products.find((x) -> x.id == parseInt(id))
    index = stage.products.indexOf(product)
    stage.products.splice(index, 1)
    this.recalcStage(stage.number)

  updateTemplateValue: (template) ->
    product = @scope.selectedProduct
    product = @scope.selectedEditProduct if product == null
    angular.forEach product.sets, (set,k) ->
      angular.forEach set.items, (item, k) ->
        item.quantity = template.quantity if item.id == template.id

    @toaster.error('Необходимо указать количество составляющих для сметного продукта') if template.quantity == ''

  # Basic logic

  getProducts: (stage) ->
    @scope.products[stage - 1]

  getProduct: (id) ->
    products = @scope.products
    product  = undefined
    $.each products, (i,v) ->
      if product == undefined
        product = v.find((x) -> x.id == parseInt(id))
    product

  getSet: (id, sets) ->
    set = undefined
    if set == undefined
      set = sets.find((x) -> x.id == parseInt(id))
    set

  getPriceByArea: (price) ->
    estimate = @scope.estimate
    return 0 if price == 0 || estimate.area == 0
    (price / estimate.area).toFixed(2)

  getStagePrice: (stage) ->
    if stage.number == 1
      price = this.getStage(1).price
    else
      previous_stage = this.getStage(stage.number - 1)
      price = parseFloat(this.getStageDiscountPrice(previous_stage)) + stage.price
    parseFloat(price).toFixed(2)

  getStageDiscountPrice: (stage) ->
    price = 0
    for i in [1..stage.number]
      price += this.getStage(i).price_with_discount
    price.toFixed(2)

  getDiscountValue: (stage) ->
    discount = @scope.discount
    estimate = @scope.estimate
    (stage.price * discount.values[stage.number - 1] / 100).toFixed(2)

  getProductFromStage: (product_id) ->
    stages = @scope.stages
    product = undefined
    $.each(stages, (i,v) ->
      if product == undefined
        product = v.products.find((x) -> x.id == parseInt(product_id))
    )
    product

  getStage: (number) ->
    @scope.stages.find((x) -> x.number == number)

  setSelectedProduct: () ->
    product_id = @scope.selectedProductId
    if product_id != 'Выберите сметный продукт'
      product = this.getProduct(product_id)
      @scope.selectedProduct = product
      @scope.selectedProductCustom = product.custom
    else
      $('#productHint').collapse('hide')
      @scope.selectedProduct = null

  setSelectedSet: () ->
    product = @scope.selectedProduct
    set_id = @scope.selectedSetId
    if set_id != 'Выберите сборку'
      selected_set = $.extend({}, this.getSet(set_id, product.sets))
      $.each(selected_set.items, (i, v) -> v.quantity = 0 )
      @scope.selectedSet = selected_set
    else
      @scope.selectedSet = null

  setSelectedEditSet: () ->
    set_id = @scope.selectedEditSetId
    stage = this.getStage(@scope.currentStage)
    product = @scope.selectedEditProduct

    $.each(product.sets, (i,v) ->
      product.sets[i].selected = v.id == set_id
      true
    )
    @scope.selectedEditSet = this.getSet(set_id, @scope.selectedEditProduct.sets)
    this.recalcProduct()

  # Recalc logic

  recalcStage: (number) ->
    product = @scope.selectedEditProduct
    @toaster.error('Необходимо указать количество сметного продукта') if product != null && product.quantity == ''

    discount    = @scope.discount
    stage       = this.getStage(number)
    stage.price = 0
    $.each(stage.products, (i,p) ->
      if p.custom
        stage.price += p.price
      else
        stage.price += p.price * p.quantity
    )
    if discount.values[number - 1] < 0
      discount.values[number - 1] = 0

    discount = discount.values[number - 1]
    stage.price_with_discount = stage.price - (stage.price * discount / 100)

    this.recalEstimate()

  recalEstimate: () ->
    estimate = @scope.estimate
    stages   = @scope.stages
    estimate.price = 0
    $.each(stages, (i,v) -> estimate.price += v.price_with_discount)
    this.saveJsonValue()

  productPrice: (product) ->
    expense = @scope.expense
    if product.price == 0
      original_product = this.getProduct(product.id)
      if product.with_work
        price = original_product.price_with_work
      else
        price = original_product.price_without_work
      original_product_price = price + (price / 100 * (expense.percent + original_product.profit))
      product.price = parseFloat(original_product_price)
      for i in [1..3]
        this.recalcStage(i)

    (product.price * product.quantity).toFixed(2)

  recalcProduct: (template) ->
    this.updateTemplateValue(template) unless template == undefined

    expense = @scope.expense
    stage   = @scope.currentStage
    product = @scope.selectedEditProduct

    product.price_with_work    = 0
    product.price_without_work = 0

    $.each(product.sets, (i,v) ->
      if v.selected
        $.each(v.items, (y,x) ->
          product.price_with_work    += parseFloat(x.quantity) * x.value.price
          product.price_without_work += parseFloat(x.quantity) * x.value.price unless x.value.work_primitive
        )
    )

    if product.with_work
      price = product.price_with_work
    else
      price = product.price_without_work
    product.price = price + (price / 100 * (expense.percent + product.profit))

    this.recalcStage(stage)

  recalcProductPrice: (stage, product) ->
    if product.with_work
      price = product.price_with_work
    else
      price = product.price_without_work
    product.price = price + (price / 100 * (@scope.expense.percent + product.profit))
    this.recalcStage(stage.number)

  saveJsonValue: () ->
    $('#estimate_json_stages').val(JSON.stringify(@scope.stages))
    true

  # Init data

  initModals: () ->
    @scope.currentStage              = null
    @scope.selectedProduct           = null
    @scope.selectedProductId         = 'Выберите сметный продукт'
    @scope.selectedProductUnit       = null
    @scope.selectedProductCustom     = false
    @scope.selectedSet               = null
    @scope.selectedSetId             = 'Выберите сборку'

    @scope.selectedEditProduct       = null
    @scope.selectedEditProductId     = null
    @scope.selectedEditProductCustom = false
    @scope.selectedEditSet           = null
    @scope.selectedEditSetId         = 'Выберите сборку'

    @scope.addModal  = { header: 'Добавление сметного продукта.',     products: [] }
    @scope.editModal = { header: 'Редактирование сметного продукта.', products: [] }

  parseEstimate: () ->
    @scope.estimate = {
      area:  parseFloat(@scope.estimate.area),
      price: parseFloat(@scope.estimate.price),
      second_floor: @scope.estimate.second_floor,
    }

  parseProducts: () ->
    products = @scope.products
    $.each(products, (i,stages) ->
      $.each(stages, (i,product) ->
        stages[i].price_with_work    = parseFloat(product.price_with_work)
        stages[i].price_without_work = parseFloat(product.price_without_work)
        stages[i].profit             = parseFloat(product.profit)

        $.each(product.sets, (i,set) ->
          $.each(set.items, (i, item) ->
            set.items[i].value.price = parseFloat(item.value.price)
          )
        )
      )
    )

  parseExpense: () ->
    @scope.expense.percent = parseFloat(@scope.expense.percent)

  parseDiscount: () ->
    discount        = @scope.discount
    discount.values = discount.values.map((x) -> parseFloat(x))

  parseStages: () ->
    self    = this
    stages  = @scope.stages
    expense = @scope.expense

    $.each(stages, (i,stage) ->
      stages[i].price               = parseFloat(stage.price)
      stages[i].price_with_discount = parseFloat(stage.price_with_discount)
      $.each(stage.products, (i,product) ->
        product.quantity = parseFloat(product.quantity)
        $.each(product.sets, (i,set) ->
          $.each(set.items, (i,item) ->
            set.items[i].value.price = parseFloat(item.value.price)
          )
        )

        if stage.products[i].custom
          price_with_work = 0
          price_without_work = 0

          quantities = []

          $.each(product.sets, (i,set) ->
            if set.selected
              $.each(set.items, (i,item) ->
                quantity = parseFloat(item.quantity)
                item.quantity = quantity
                quantities.push(quantity)
                price_with_work += parseFloat(item.value.price) * parseFloat(item.quantity)
                price_without_work += parseFloat(item.value.price_without_work) * parseFloat(item.quantity)
              )
          )

          $.each(product.sets, (i,set) ->
            unless set.selected
              $.each(set.items, (i,item) ->
                item.quantity = quantities[i]
              )
          )

          stage.products[i].price_with_work     = price_with_work
          stage.products[i].price_without_work  = price_without_work
          stage.products[i].profit = parseFloat(product.profit)
          if product.with_work
            price = price_with_work
          else
            price = price_without_work
          stage.products[i].price = price + (price / 100 * (expense.percent + product.profit))
        else
          stage.products[i].price_with_work     = parseFloat(product.price_with_work)
          stage.products[i].price_without_work  = parseFloat(product.price_without_work)
          stage.products[i].profit              = parseFloat(product.profit)
          if product.with_work
            price = parseFloat(product.price_with_work)
          else
            price = parseFloat(product.price_without_work)
          stage.products[i].price = price + (price / 100 * (expense.percent + product.profit))
      )
    )
