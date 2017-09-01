require 'test_helper'

class RecordControllerTest < ActionController::TestCase
  test 'should get record' do
    VCR.use_cassette('record: bananas', allow_playback_repeats: true) do
      get :record, params: { db_source: 'cat00916a', an: 'mit.001492509' }
      assert_response :success
    end
  end

  test 'should handle missing parameters' do
    get :record, params: { db_source: 'dog00916a' }
    assert_response :redirect
  end

  test 'should handle invalid parameters' do
    VCR.use_cassette('record: no such database',
                     allow_playback_repeats: true) do
      assert_raises ActionController::RoutingError do
        get :record, params: { db_source: 'dog00916a', an: 'mit.001492509' }
      end
    end
  end
end
