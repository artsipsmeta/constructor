require 'rtf'

class Budget < ApplicationRecord
  include RTF
  include ApplicationHelper

  FLOOR_NAME = {
    '1'   => 'Одноэтажный',
    '1.5' => 'Одноэтажный с мансардой',
    '2'   => 'Двухэтажный',
    '2.5' => 'Двухэтажный с мансардой',
    '3'   => 'Трехэтажный'
  }.freeze

  AREA_MIN  = 10
  AREA_MAX  = 250
  AREA_STEP = 20

  scope :by_floor,    -> (floor)      { where('floors = ?', floor) }
  scope :only_signed, ->              { where('signed') }
  scope :date_start,  -> (date_start) { where('signing_date >= ?', date_start.to_datetime - 1.day) if date_start.present? }
  scope :date_end,    -> (date_end)   { where('signing_date <= ?', date_end.to_datetime + 1.day) if date_end.present? }
  scope :area_start,  -> (area_start) { where('area >= ?', area_start) if area_start.present? }
  scope :area_end,    -> (area_end)   { where('area < ?', area_end) if area_end.present? }

  validates :name,               presence: true, length: { in: 2..256 }
  validates :area,               presence: true, numericality: { greater_than: 0 }
  validates :area,               float_with_precision_two: true
  validates :first_floor_height, presence: true, numericality: { greater_than: 0 }, float_with_precision_three: true

  validates :second_floor_height_min, numericality: { less_than_or_equal: :second_floor_height_max }, float_with_precision_three: true
  validates :second_floor_height_max, numericality: { greater_than_or_equal_to: 0 }, float_with_precision_three: true
  validates :third_floor_height_min, numericality: { less_than_or_equal: :third_floor_height_max }, float_with_precision_three: true
  validates :third_floor_height_max, numericality: { greater_than_or_equal_to: 0 }, float_with_precision_three: true

  belongs_to :solution
  belongs_to :user,     -> { with_deleted }
  belongs_to :proposer, -> { with_deleted }, class_name: 'User', foreign_key: :proposer_id

  has_many :stages
  has_many :client_files
  has_many :technical_files

  accepts_nested_attributes_for :client_files, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :technical_files, reject_if: :all_blank, allow_destroy: true

  before_save :fill_empty_fields
  before_destroy :clear_relationships

  def fill_empty_fields
    self.discount_by_stages = [0, 0, 0] if discount_by_stages == ['', '', '']
  end

  def clear_relationships
    stages.each.each(&:destroy)
  end

  def calc_parameters
    self.price_by_area = (self.price / self.area).round 2 if self.area > 0
    self.price_by_stage_aggregated[0] = price_by_stage[0]
    self.price_by_stage_aggregated[1] = price_by_stage_aggregated[0] + price_by_stage[1]
    self.price_by_stage_aggregated[2] = price_by_stage_aggregated[1] + price_by_stage[2]
    discount_all = 0
    (0..2).each do |i|
      self.price_by_area_per_stage[i] = (self.price_by_stage_aggregated[i] / self.area).round 2 if self.area > 0
      self.discount_amount[i] = (self.price_by_stage[i] * self.discount_by_stages[i] / 100.0).round(2)
      discount_all += self.discount_amount[i]
      self.price_by_stage_aggregated_discounted[i] = self.price_by_stage_aggregated[i] - discount_all
      self.price_by_area_per_stage_discounted[i] = (self.price_by_stage_aggregated_discounted[i] / area).round(2)
    end
    self.second_floor_height_min ||= 0
    self.second_floor_height_max ||= 0
    self.third_floor_height_min  ||= 0
    self.third_floor_height_max  ||= 0
    self.floors = self.get_floor
    self.save
  end

  def get_stages
    if self.new_record?
      new_stages = []
      (1..3).each do |i|
        new_stages.push(
          number:              i,
          text:                get_stage_text(i),
          products:            [],
          price:               0,
          price_with_discount: 0
        )
      end
      new_stages
    else
      stages.order(:number).includes(:stage_products).map do |stage|
        {
          number:              stage.number,
          text:                get_stage_text(stage.number),
          price:               stage.price,
          price_with_discount: stage.price_with_discount,
          products:            stage.stage_products.order(:id).includes(:stage_product_sets, :product, product: [:unit] ).map do |stage_product|
            {
              id:                 stage_product.product.id,
              name:               stage_product.product.name,
              unit:               stage_product.product.unit.name,
              custom:             stage_product.product.custom,
              hint:               stage_product.product.hint,
              profit:             stage_product.product.profit,
              price_with_work:    stage_product.product.price,
              price_without_work: stage_product.product.price_without_work,
              with_work:          stage_product.with_work,
              quantity:           stage_product.quantity,
              sets:               stage_product.product.custom ? get_stage_product_set(stage_product) : []
            }
          end
        }
      end
    end
  end

  def get_stage_product_set(stage_product)
    stage_product.stage_product_sets.order(:id).includes(:stage_product_set_values).map do |product_set|
      {
        id:       product_set.product_set.id,
        name:     product_set.product_set.name,
        selected: product_set.selected,
        items: product_set.stage_product_set_values.order(:id).includes(:product_template, :constructor_object, constructor_object: [:unit]).map do |item|
          {
            id:       item.product_template.id,
            name:     item.product_template.name,
            quantity: item.quantity,
            value: {
              id:     item.constructor_object.id,
              name:   item.constructor_object.name,
              unit:   item.constructor_object.unit.name,
              price:  item.constructor_object.price,
              price_without_work: item.constructor_object.price_without_work,
              work_primitive: item.constructor_object.work_primitive?
            }
          }
        end
      }
    end
  end

  def get_stage_text(number)
    case number
    when 1
      {
        name:     'Первый этап',
        summ:     'Итого по первому этапу:',
        summ_dis: 'по первому этапу',
        discount: 'Итого по первому этапу со скидкой:'
      }
    when 2
      {
        name:     'Второй этап',
        summ:     'Итого по двум этапам:',
        summ_dis: 'по второму этапу',
        discount: 'Итого по двум этапам со скидкой:'
      }
    when 3
      {
        name:     'Третий этап',
        summ:     'Итого по трем этапам:',
        summ_dis: 'по третьему этапу',
        discount: 'Итого по трем этапам со скидкой:'
      }
    end
  end

  def get_floor
    return 3   if third_floor_height_min  > 0 && third_floor_height_min  > 1.8
    return 2.5 if third_floor_height_min  > 0 && third_floor_height_min  < 1.8
    return 2   if second_floor_height_min > 0 && second_floor_height_min > 1.8
    return 1.5 if second_floor_height_min > 0 && second_floor_height_min < 1.8
    1
  end

  def to_s
    name
  end

  def update_report_primitivies
    ReportPrimitive.where( estimate_id: self.id).destroy_all
    self.stages.each do |stage|
      stage.update_report_primitivies
    end
  end

  def for_export_budget
    data = {
      discount_title: self.discount_title,
      discount_amount: self.discount_amount,
      price_by_stage_aggregated: self.price_by_stage_aggregated,
      price_by_area_per_stage: self.price_by_area_per_stage,
      price_by_stage_aggregated_discounted: self.price_by_stage_aggregated_discounted,
      price_by_area_per_stage_discounted: self.price_by_area_per_stage_discounted,
      project: self.name,
      date: self.created_at,
      area:  self.area,
      price: self.price,
      first_floor_height: self.first_floor_height,
      second_floor_height_min: self.second_floor_height_min,
      second_floor_height_max: self.second_floor_height_max,
      third_floor_height_min: self.third_floor_height_min,
      third_floor_height_max: self.third_floor_height_max,
      stages_many: self.stages.active.count > 1,
      stages: self.stages.includes(:stage_products).map do |stage|
        {
          number:              stage.number,
          current_text:        Stage::CURRENT[stage.number-1],
          discount_text:       Stage::DISCOUNT[stage.number-1],
          all_text:            Stage::ALL[stage.number-1],
          price_with_discount: stage.price_with_discount,
          price:               stage.price,
          products:            stage.stage_products.order(:id).includes(:stage_product_sets, :product, product: [:unit] ).map do |stage_product|
            {
              name:               stage_product.product.name,
              description:        stage_product.product.description,
              display_components: stage_product.product.display_components,
              custom:             stage_product.product.custom,
              with_work:          stage_product.with_work,
              unit:               stage_product.product.unit.name,
              price_result:       stage_product.price,
              quantity:           stage_product.quantity.to_i,
              set_name:           stage_product.product.custom ? stage_product.stage_product_sets.find_by(selected: true).product_set.name : '',
              sets:               stage_product.product.custom ? self.get_stage_product_set(stage_product) : [],
              items:              stage_product.items
            }
          end
        }
      end
    }

    data[:stages].sort_by! { |s| s[:number] }.to_a
    data[:stages].each_with_index do |stage, index|
      next if index.zero?
      stage[:price] = stage[:price] + data[:stages][index - 1][:price_with_discount]
      stage[:price_with_discount] = stage[:price_with_discount] + data[:stages][index - 1][:price_with_discount]
    end
    data
  end

  def solution?
    type == 'Solution'
  end

  def rtf(current_user)
    data = for_export_budget

    styles                           = {}

    styles['DOCUMENT'] = DocumentStyle.new
    styles['DOCUMENT'].bottom_margin = 1000
    styles['DOCUMENT'].left_margin   = 1000
    styles['DOCUMENT'].right_margin  = 1000
    styles['DOCUMENT'].top_margin    = 1000

    styles['PS_HEADER_LEFT']               = ParagraphStyle.new
    styles['PS_HEADER_LEFT'].justification = ParagraphStyle::RIGHT_JUSTIFY
    styles['CS_HEADER_LEFT']               = CharacterStyle.new
    styles['CS_HEADER_LEFT'].font_size     = 10


    styles['CS_TABLE_HEAD']               = CharacterStyle.new
    styles['CS_TABLE_HEAD'].font_size     = 100
    styles['CS_TABLE_HEAD'].bold          = true


    styles['NORMAL']                 = ParagraphStyle.new
    styles['NORMAL'].space_after     = 100

    styles['TITLE']                 = ParagraphStyle.new
    styles['TITLE'].justification   = ParagraphStyle::CENTER_JUSTIFY

    styles['PS_SUMMARY']               = ParagraphStyle.new
    styles['PS_SUMMARY'].justification = ParagraphStyle::CENTER_JUSTIFY

    styles['CS_SUMMARY']               = CharacterStyle.new
    styles['CS_SUMMARY'].bold          = true

    styles['CS_DISCOUNT']               = CharacterStyle.new
    styles['CS_DISCOUNT'].bold          = true
    styles['CS_DISCOUNT'].foreground    = Colour.new(255, 0, 0)

    styles['PS_STAGE_NUMBER']               = ParagraphStyle.new
    styles['PS_STAGE_NUMBER'].justification = ParagraphStyle::CENTER_JUSTIFY
    styles['CS_STAGE_NUMBER']               = CharacterStyle.new
    styles['CS_STAGE_NUMBER'].foreground    = Colour.new(255, 165, 0)
    styles['CS_STAGE_NUMBER'].font_size     = 36

    styles['PS_STAGE_NAME']               = ParagraphStyle.new
    styles['PS_STAGE_NAME'].justification = ParagraphStyle::CENTER_JUSTIFY
    styles['CS_STAGE_NAME']               = CharacterStyle.new
    styles['CS_STAGE_NAME'].font_size     = 36

    styles['PS_TEXT']               = ParagraphStyle.new
    styles['PS_TEXT'].justification = ParagraphStyle::FULL_JUSTIFY
    styles['PS_TEXT'].space_after   = 200

    styles['H3']                    = CharacterStyle.new
    styles['H3'].bold               = true
    styles['H3'].font_size          = 36

    styles['PS_OFFSET']               = ParagraphStyle.new
    styles['PS_OFFSET'].space_after = 300

    document = Document.new(Font.new(Font::ROMAN, 'Times New Roman'), styles['DOCUMENT'])

    # шапка документа
    table = document.table(1, 3, 3500, 3500, 3500)
    table.border_width = 0

    left_column = ['РФ, Республика Крым', 'г. Симферополь', 'ул. Петропавловская, дом 3', 'ТДЦ "Октябрьский", офис 411/412']
    right_column = ['www.artsipstroi.com', 'www.artkarkas.ru', current_user.email, current_user.phone]

    left_column.each do |row|
      table[0][0] << row
      table[0][0].line_break if row != left_column.last
    end

    image = table[0][1].image("#{Rails.root}/app/assets/images/full-logo.png")
    image.x_scaling = 50
    image.y_scaling = 50

    right_column.each do |row|
      table[0][2] << row
      table[0][2].line_break if row != left_column.last
    end

    # название
    document.paragraph(styles['TITLE']) do |p|
       p.apply(styles['H3']) do |t|
        t << 'Расчет стоимости строительства'
        t.line_break
        t << 'энергосберегающего жилого дома'
      end
    end
    document.paragraph(styles['PS_OFFSET'])

    # информация по смете
    table = document.table(1, 3, 3500, 3500, 3500)
    table.border_width = 0

    table[0][0] << "Высота потолка первого этажа: #{data[:first_floor_height]} м"
    table[0][0].line_break
    if data[:second_floor_height_min] > 0 && data[:second_floor_height_max] > 0
      table[0][0] << "Высота потолка второго этажа: от #{data[:second_floor_height_min]} м до #{data[:second_floor_height_max]} м"
      table[0][0].line_break
    end
    if self.second_floor_height_min > 0 && self.second_floor_height_max > 0
      table[0][0] << "Высота потолка третьего этажа: от #{data[:third_floor_height_min]} м до #{data[:third_floor_height_max]} м"
      table[0][0].line_break
    end
    table[0][0] << "Площадь строительства: #{data[:area]} м2"
    table[0][2] << "Дата расчета: #{data[:date].strftime('%d %B %Y')} г."


    stages_text = [
      { title: 'Первый этап', name: 'Фундамент/коробка/кровля', pluralize: 'этапу'},
      { title: 'Второй этап', name: 'Под отделку', pluralize: 'этапам'},
      { title: 'Третий этап', name: 'Под чистовую внутреннюю отделку', pluralize: 'этапам'}
    ]
    document.paragraph(styles['PS_OFFSET'])

    # этапы
    data[:stages].each do |stage|
      unless stage[:products].empty?

        document.paragraph(styles['PS_STAGE_NUMBER']) do |p|
          p.apply(styles['CS_STAGE_NUMBER']) do |t|
            t << stages_text[stage[:number]-1][:title]
          end
        end

        document.paragraph(styles['TITLE']) do |p|
          p.apply(styles['CS_STAGE_NAME']) do |t|
            t << stages_text[stage[:number]-1][:name]
          end
        end

        table    = document.table(stage[:products].size+1, 2, 6500, 4000)
        table.border_width = 5
        table[0][0].apply(styles['CS_TABLE_HEAD'])
        table[0][0] << 'Наименование'
        table[0][1].apply(styles['CS_TABLE_HEAD'])
        table[0][1] << 'Стоимость'

        i = 1
        stage[:products].each do |product|
          table[i][0] << product[:name] + (product[:custom] ? " | #{product[:set_name]}" : (product[:display_components] ? ", #{product[:quantity].to_s} #{product[:unit]}" : ""))
          if product[:custom] && product[:display_components]
            product[:items].each do |item|
              table[i][0].line_break
              table[i][0] << "- #{item[:name]} - #{item[:quantity].to_s} #{item[:unit]}"
            end
          end
          table[i][0].line_break
          table[i][0] << product[:description] + (product[:with_work] ? ", монтаж" : ", без монтажа")
          table[i][1] << money(product[:price_result] * product[:quantity])
          i += 1
        end
        document.paragraph(styles['PS_SUMMARY']) do |p|
          p.apply(styles['CS_SUMMARY']) do |r|
            r << "Итого по #{stage[:number]} этапу: #{money(data[:price_by_stage_aggregated][stage[:number]-1])} руб. (~ #{money(data[:price_by_area_per_stage][stage[:number]-1])} руб. за м2)"
          end
        end
        if data[:discount_amount][stage[:number]-1] > 0
          document.paragraph(styles['PS_SUMMARY']) do |p|
            p.apply(styles['CS_DISCOUNT']) do |r|
              r << "#{data[:discount_title]} по #{stage[:number]} этапу: -#{money(data[:discount_amount][stage[:number]-1])} руб."
            end
          end
        end
        document.paragraph(styles['PS_SUMMARY']) do |p|
          p.apply(styles['CS_SUMMARY']) do |r|
            r << "Итого по #{stage[:number]} #{stages_text[stage[:number]-1][:pluralize]}: #{money(data[:price_by_stage_aggregated_discounted][stage[:number]-1])} руб. (~ #{money(data[:price_by_area_per_stage_discounted][stage[:number]-1])} руб. за м2)"
          end
        end
      end
      document.paragraph(styles['PS_OFFSET'])
    end

    document.paragraph(styles['PS_TEXT']) do |p|
      p << "Доставка по всему Крыму – бесплатно. Гарантия на дом — 10 лет. Срок эксплуатации – 70 лет. Только сертифицированные и качественные строительные материалы."
    end
    if data[:area] > 99
      document.paragraph(styles['PS_TEXT']) do |p|
        p << "Черновая рабочая лестница из сосны камерной сушки В ПОДАРОК!"
      end
    end

    unless data[:stages].third[:products].empty?
      document.paragraph(styles['PS_TEXT']) do |p|
        p << "Внутридомовые инженерные сети (вода, канализация, а также электроразводка по дому) детально просчитываются после выполнения первого этапа и уточнения всех
          деталей с Заказчиком В общей стоимости здания данные позиции суммарно занимают ориентировочно 3-6%."
      end
    end
    document.to_rtf
  end
end
