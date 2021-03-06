
# Given an item, the ButtonMaker does the following:
# * checks its eligibility for all actions
# * when eligible, creates the HTML for a button powering that action
# all_buttons returns the list of buttons thus created.
# This means that we don't have to do any complex logic in the HTML - we can
# just iterate through all available buttons and display them.
# Important features:
# @options is a list of the names of each action that might be available for an
# item.
# For each action in options, the following functions must exist:
# * eligible_for_#{action}? - returns true/false
# * make_button_for_#{action} - returns HTML of relevant button
# This should probably have related to the Great Not-Completed AlephObject
# Refactor, but it just got too janky to deal with all the edge cases in our
# circ logic - too hard to tell whether they'd all been dealt with, except by
# pulling it all into a special-purpose, encapsulated place.
class ButtonMaker
  def initialize(item, oclc)
    @item = item
    @oclc = oclc
    @options = %w(call contact hold ill recall scan special_ill)

    # Properties of items. This must go *after* setting @item and @oclc, but
    # *before* setting @requestable.
    set_item_properties

    @requestable = requestable?
  end

  def set_item_properties
    @barcode = @item.xpath('z30/z30-barcode').text
    @call_number = @item.xpath('z30/z30-call-no').text
    @collection = @item.xpath('z30/z30-collection').text
    @doc_number = @item.xpath('z30/z30-doc-number').text
    @identifier = clean_identifier # May be ISBN or ISSN
    @item_sequence = @item.xpath('z30/z30-item-sequence').text
    @library = @item.xpath('z30/z30-sub-library').text
    @oclc_number = clean_oclc
    @on_reserve = (@collection == 'Reserve Stacks')
    @status = @item.xpath('status').text
    @title = @item.xpath('z13/z13-title').text
    @z30status = @item.xpath('z30/z30-item-status').text
    # Yes, this excludes `z30/` on purpose.
    @z30status_code = @item.xpath('z30-item-status-code').text
  end

  def all_buttons
    buttons = []
    @options.each do |option|
      eligibility_func = "eligible_for_#{option}?"
      if method(eligibility_func).call
        button_func = "make_button_for_#{option}"
        buttons << method(button_func).call
      end
    end
    buttons
  end

  # ~~~~~~~~~~~~~~~~ Eligibility determination functions ~~~~~~~~~~~~~~~~
  def eligible_for_contact?
    @library == 'Institute Archives'
  end

  def eligible_for_call?
    @on_reserve
  end

  def eligible_for_hold?
    return false if @on_reserve
    [
      # You can request things that are in the library and have reasonable
      # loan policies.
      @status == 'In Library' && @requestable,
      # You can also request things that are in the library and are currently
      # part of special displays.
      ['MIT Reads', 'New Books Displ', 'On Display'].include?(@status)
    ].any?
  end

  # Can you request that this item be ordered via ILL?
  # Items must have an OCLC number to be ILLable. Items that are in the library
  # now and can simply be borrowed, with reasonable loan terms, may not be
  # ILLed. (Items that are in the library but have extremely short-term loan
  # periods, such as two hours, are eligible for ILL in case patrons need them
  # for a while. Those statuses are deliberately excluded from the `none?`
  # status checker.
  # Items eligible this way may ultimately be ordered via either BorrowDirect
  # or ILLiad.
  def eligible_for_ill?
    badz30 = [
      '1 Day Loan',
      '1 Week No Renew',
      '1 Week No Renew Equip',
      '2 Day Loan',
      '24 Hour Loan',
      '3 Day Loan',
      'Audio Recorder',
      'Due at Closing',
      'Journal Loan',
      'Music CD/DVD',
      'Pass',
      'See Note Above',
      'Two Week Loan'
    ]

    # If it has a disqualifying status, you can't ILL it. If it doesn't, you're
    # good to go.
    [
      eligible_for_hold?,
      @status == 'Received',
      badz30.include?(@z30status)
    ].none?
  end

  def eligible_for_recall?
    return false if @on_reserve
    # It's not enough to say `@status != 'In Library'`, because the item might
    # have a status of 'On Order' or 'Missing', and those are not recallable.
    @status.start_with?('Due') && @requestable
  end

  # We do not allow patrons to request electronic scans of all materials.
  # Sometimes this is a policy issue; sometimes it's a physical impossibility
  # issue, like "item is not in the library right now" or "item is an audio
  # tape".
  def eligible_for_scan?
    [
      call_number_valid_for_scan?,
      z30status_valid_for_scan?,
      collection_valid_for_scan?,
      status_valid_for_scan?,
      library_valid_for_scan?
      # We should also exclude the subject header 'Standards, Engineering',
      # but we don't have subject headers in the Aleph data, so we aren't.
    ].all?
  end

  # Some items are eligible for ILL (albeit only through BorrowDirect) even
  # though they are also available in the library.
  # Unfortunately we don't know if these items are actually *available* in BD.
  def eligible_for_special_ill?
    return false if eligible_for_ill? # We don't want to display both buttons.
    goodz30 = [
      'Room Use Only',
      '4 Hour Reserves',
      '2 Hour Loan',
      'Fall 2 Hours',
      'Spring 2 Hours',
      'IAP 2 Hours',
      'Summer 2 Hours'
    ]
    @status == 'In Library' && goodz30.include?(@z30status)
  end

  # ~~~~~~~~ Functions which return HTML for availability action buttons ~~~~~~~

  # The following functions construct URLs needed for item availability actions.
  # WE NEED THESE EVEN IF WE REFACTOR TO RELY MORE ON EBSCO RESULTS - they
  # require Aleph data which is not known to EBSCO.
  # These URLs will present authentication challenges for non-logged-in users,
  # which will redirect appropriately upon success.

  def make_button_for_call
    # Mapping from @library to URL path.
    path_options = {
      'Barker Library' => 'barker',
      'Dewey Library' => 'dewey',
      'Institute Archives' => 'archives',
      'Hayden Library' => 'hayden',
      'Lewis Music Library' => 'music',
      'Library Storage Annex' => 'lsa',
      'Rotch Library' => 'rotch'
    }
    return unless path_options.key?(@library)
    path = path_options[@library]
    "<a class='btn button-secondary button-small' " \
      "href='https://libraries.mit.edu/#{path}/'>Call Us</a>"
  end

  def make_button_for_contact
    "<a class='btn button-secondary button-small' " \
      "href='https://libraries.mit.edu/archives/'>Contact Us</a>"
  end

  def make_button_for_hold
    "<a class='btn button-secondary button-small' " \
      "href='#{url_for_hold}'>Place Hold</a>"
  end

  def make_button_for_ill
    "<a class='btn button-secondary button-small' "\
      "href='#{url_for_ill}'>Get it with ILL (3-4 days)</a>"
  end

  def make_button_for_recall
    # Yes, the hold URL and the recall URL are the same.
    "<a class='btn button-subtle button-small' " \
      "href='#{url_for_hold}'>Recall (7+ days)</a>"
  end

  def make_button_for_scan
    "<a class='btn button-secondary' href='#{url_for_scan}'>Request Scan</a>"
  end

  def make_button_for_special_ill
    "<a class='btn button-secondary button-small' "\
      "href='#{url_for_special_ill}'>Get it with ILL (3-4 days)</a>"
  end

  # ~~~~~~~~ Functions which create URLs for availability action buttons ~~~~~~~
  def url_for_hold
    queryarray = { func: 'item-hold-request',
                   doc_library: 'MIT50',
                   adm_doc_number: @doc_number,
                   item_sequence: @item_sequence }

    url = URI::HTTP.build(host: 'library.mit.edu',
                          path: '/F',
                          query: queryarray.to_query)
    url.to_s
  end

  def url_for_scan
    analytics = 'BENTO'
    encoded_title = ERB::Util.url_encode(ERB::Util.url_encode(@title))

    # The call number is important! In Barton we use different URL parameters
    # for request items, but this ends up with scan requests for Technique
    # (the yearbook) being routed to a Polish land use journal. Call number
    # fixes this bug and does not seem to introduce new ones.
    encoded_call_no = ERB::Util.url_encode(@call_number)

    [
      sfx_host.to_s,
      "?sid=ALEPH:#{analytics}",
      "&amp;call_number=#{encoded_call_no}",
      '&amp;genre=journal',
      "&amp;barcode=#{@barcode}",
      "&amp;title=#{encoded_title}",
      "&amp;location=#{encoded_location}"
    ].join('')
  end

  def url_for_ill
    return unless @oclc_number.present?
    "https://mit.worldcat.org/search?q=no%3A#{@oclc_number}"
  end

  # special_ill items are only eligible via BorrowDirect.
  def url_for_special_ill
    # @identifier may be an ISBN or the ISSN, but either one works in the BD
    # ISBN parameter.
    'https://library.mit.edu/shib/bd.cgi?url_ver=Z39.88-2004' \
      "&amp;rft.isbn=#{@identifier}"
  end

  # ~~~~~~~~ Utility functions needed to determine PDF scan eligibility ~~~~~~~~
  def call_number_valid_for_scan?
    !@call_number.start_with?('ARCH DRAW', 'ATLAS', 'AUDIO', 'AUDTAPE', 'CD',
                              'CDROM', 'DSKETTE', 'DVD', 'DVDROM', 'FICHE',
                              'FILM', 'FOLIO', 'INDEX', 'MAP', 'MFILM',
                              'OVRSIZE', 'RECORD', 'REGULAR', 'SCORE', 'SMALL',
                              'THESIS', 'USB DRIVE', 'VDISC', 'VIDEO')
  end

  def z30status_valid_for_scan?
    [
      '60 Day Loan',
      'One Week Loan',
      '1 Week No Renew',
      'OCC 60',
      'LSA 7',
      'LSA 60',
      'LSA Use Only'
    ].include? @z30status
  end

  def collection_valid_for_scan?
    [
      'Stacks',
      'Journal Collection',
      'Off Campus Collection',
      'Science Journals',
      'Humanities Journals',
      'Impulse Borrowing Display',
      'Browsery',
      'Graphic Novel Collection',
      'Travel Collection'
    ].include? @collection
  end

  def status_valid_for_scan?
    ['In Library', 'New Books Displ'].include?(@status)
  end

  def library_valid_for_scan?
    ['Physics Dept. Reading Room', 'Rotch Visual Collections',
     'Institute Archives'].exclude? @library
  end

  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Misc utilities ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  # Items with these process & item statuses may be put on hold/recalled.
  def requestable?
    return false if @on_reserve
    [
      # Items with these status codes may be requested from any library,
      # except the Annex.
      %w(01 03 04 05 06 07 08 09 11 12 19 20 21).include?(@z30status_code) &&
        @library != 'Library Storage Annex',

      # Items with status code 23 may be requested from only some libraries.
      @z30status_code == '23' && ['Barker Library',
                                  'Dewey Library',
                                  'Hayden Library',
                                  'Rotch Library',
                                  'Library Storage Annex'].include?(@library),

      # The Annex is special.
      %w(13 14 15 56 57).include?(@z30status_code) &&
        @library == 'Library Storage Annex'
    ].any?
  end

  def sfx_host
    if Rails.env.production?
      'https://sfx.mit.edu/sfx_local'
    else
      'https://sfx.mit.edu/sfx_test'
    end
  end

  def encoded_location
    location = if @collection == 'Off Campus Collection'
                 'OCC'
               else
                 @library
               end
    ERB::Util.url_encode(ERB::Util.url_encode(location))
  end

  def clean_oclc
    return unless @oclc.present?
    # @record.eds_document_oclc may return a list of OCLC numbers as encoded
    # HTML (e.g. `13978097&lt;br /&gt;42378644` as the OCLC for
    # `/record/cat00916a/mit.000879736`). We're just going to take the first
    # one and hope for the best.
    # If there is no match, this will return an empty string.
    /[0-9]*/.match(@oclc)[0]
  end

  def clean_identifier
    # The isbn_issn field may contain either an ISBN or an ISSN. Furthermore,
    # it may contain junk data. (For example: `0826213391 (v. 1 : alk. paper)`
    # was seen in the wild.) This function finds the first object which is
    # either an ISBN or an ISSN.
    identifier_text = @item.xpath('z13/z13-isbn-issn').text
    isbn_regex = /(?=[0-9X]{10}|(?=(?:[0-9]+[- ]){3})[- 0-9X]{13}|97[89][0-9]{10}|(?=(?:[0-9]+[- ]){4})[- 0-9]{17}$)(?:97[89][- ]?)?[0-9]{1,5}[- ]?[0-9]+[- ]?[0-9]+[- ]?[0-9X]/
    issn_regex = /[0-9]{4}-[0-9]{3}[0-9X]/
    isbn_match = isbn_regex.match(identifier_text)
    issn_match = issn_regex.match(identifier_text)

    # This statement will assign to `identifier`, in this order of priority:
    # 1) the first plausible ISBN found; 2) the first plausible ISSN found;
    # 3) false.
    identifier = (isbn_match && isbn_match[0]) || (issn_match && issn_match[0])
    identifier || nil
  end
end
