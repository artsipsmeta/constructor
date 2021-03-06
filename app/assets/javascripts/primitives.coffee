$(document).on 'turbolinks:load', () ->
  $('.primitive-price').on 'blur', (e) ->
    price = $(e.target).val()
    id    = $(e.target).data('id')
    old_price = $(e.target).data('price')
    unless parseFloat(price) == parseFloat(old_price)
      $.ajax({
        type: "PUT",
        url:  '/primitives/' + id,
        data: { 'primitive[price]': price }
      })

  $('.update-price-link').on('click', (e) ->
    e.preventDefault()
    id = $(this).data('id')
    price = $('.primitive-price[data-id=' + id + ']').val()
    $.ajax({
      type: "PUT",
      url:  '/primitives/' + id,
      data: { 'primitive[price]': price }
    })
    .done((data) ->
      date = data.date
      id   = data.id
      button = $('.primitive-actions[data-id=' + id + ']')
      button.removeClass('btn-warning btn-danger')
            .addClass('btn-default')
            .html(date + ' <span class="caret"></span>')
    )
  )
