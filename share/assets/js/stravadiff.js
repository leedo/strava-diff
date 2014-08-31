$(document).ready(function() {
  var diff = $('#diff');

  $('input[type="radio"]').on("click", function(e) {
    var id = $(this).val();
    var side = $(this).attr("name");

    var inputs = $("input[type=radio]");
    var opposites = inputs.filter("[name=" + (side == "a" ? "b" : "a") + "]");
    opposites.filter("[disabled]").removeAttr("disabled").removeClass("selected");
    opposites.filter("[value="+id+"]").attr("disabled", "disabled");

    $("tr.selected").removeClass("selected");
    inputs.filter(":checked").parents("tr").addClass("selected");

    if (inputs.filter(":checked").length == 2) {
      var a = inputs.filter("[name=a]:checked").val()
        , b = inputs.filter("[name=b]:checked").val();
      $.ajax({
        url: "/diff/" + a + "/" + b,
        cache: true,
        dataType: "text",
        success: function(res) {
          diff.html(res);
        }
      });
    }
    else {
      $.ajax({
        url: "/activity/" + id,
        cache: true,
        dataType: "text",
        success: function(res) {
          diff.html(res);
        }
      });
    }
  });
});
