safeReady(function() {
  $("#signupInfo").hide();

  $("#tosCBox").change(function() {
    if ($("#tosCBox").attr("checked")) {
      $("#signupInfo").show();
      if ($("#signupInfo input").size() > 0)
        $("#signupInfo input")[0].focus();
    } else {
      $("#signupInfo").hide();
    }
  });
   $(".callme").change(function() {
    if ($(".callme").attr("checked")) {
      $(".phonerow").show();
    } else {
      $(".phonerow").hide();
    }
  });
});
